import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uniexam/core/token_manager.dart';

/// Attaches the access token, and transparently recovers from a 401 by refreshing.
///
/// Two details matter here:
///  * refresh runs through a *separate* Dio instance, so a failing refresh cannot
///    recurse back into this interceptor;
///  * concurrent 401s share one refresh via [_refreshing]. Without that, five parallel
///    requests would fire five refreshes, and since the server rotates refresh tokens,
///    four of them would present an already-revoked token and log the user out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenManager tokenManager,
    required Dio refreshClient,
    required Future<void> Function() onSessionExpired,
  })  : _tokens = tokenManager,
        _refreshClient = refreshClient,
        _onSessionExpired = onSessionExpired;

  static const _retriedFlag = 'uniexam.retried';

  /// Endpoints that must not carry an access token.
  static const _anonymousPaths = {'/auth/login', '/auth/refresh'};

  final TokenManager _tokens;
  final Dio _refreshClient;
  final Future<void> Function() _onSessionExpired;

  /// The Dio instance used to replay a request after a successful refresh.
  late final Dio dio;

  Future<bool>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.accessToken;
    if (token != null && !_isAnonymous(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final shouldTryRefresh = err.response?.statusCode == 401 &&
        !_isAnonymous(request.path) &&
        request.extra[_retriedFlag] != true &&
        _tokens.refreshToken != null;

    if (!shouldTryRefresh) {
      if (err.response?.statusCode == 401 && !_isAnonymous(request.path)) {
        await _onSessionExpired();
      }
      handler.next(err);
      return;
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      await _onSessionExpired();
      handler.next(err);
      return;
    }

    try {
      request.extra[_retriedFlag] = true;
      request.headers['Authorization'] = 'Bearer ${_tokens.accessToken}';
      final response = await dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _isAnonymous(String path) => _anonymousPaths.any(path.endsWith);

  Future<bool> _refreshOnce() {
    return _refreshing ??= _performRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _performRefresh() async {
    final refreshToken = _tokens.refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await _refreshClient.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data;
      if (data == null) return false;
      await _tokens.save(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );
      return true;
    } on DioException {
      return false;
    }
  }
}
