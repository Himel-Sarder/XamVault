import 'package:dio/dio.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/auth_interceptor.dart';
import 'package:uniexam/core/token_manager.dart';

/// The single configured HTTP entry point for the app.
///
/// Every repository goes through here, so timeouts, base URL, auth and error mapping are
/// defined once instead of at each call site.
class ApiClient {
  ApiClient({
    required TokenManager tokenManager,
    required Future<void> Function() onSessionExpired,
    String? baseUrl,
    Dio? inner,
    Dio? refreshClient,
  }) {
    final resolvedBaseUrl = baseUrl ?? AppConfig.apiBaseUrl;
    final options = BaseOptions(
      baseUrl: resolvedBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
      // Let the interceptor see 401s as errors; everything else is handled by callers.
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    );

    dio = inner ?? Dio();
    dio.options = options;

    // A separate client for /auth/refresh: it has no AuthInterceptor, so a 401 on
    // refresh cannot trigger another refresh.
    final refreshDio = refreshClient ?? Dio();
    refreshDio.options = options;

    _authInterceptor = AuthInterceptor(
      tokenManager: tokenManager,
      refreshClient: refreshDio,
      onSessionExpired: onSessionExpired,
    )..dio = dio;

    dio.interceptors.add(_authInterceptor);
  }

  late final Dio dio;
  late final AuthInterceptor _authInterceptor;

  AuthInterceptor get authInterceptor => _authInterceptor;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.get<T>(path, queryParameters: query));

  Future<T> post<T>(String path, {Object? data}) =>
      _send(() => dio.post<T>(path, data: data));

  Future<T> put<T>(String path, {Object? data}) =>
      _send(() => dio.put<T>(path, data: data));

  Future<T> patch<T>(String path, {Object? data}) =>
      _send(() => dio.patch<T>(path, data: data));

  /// Fetches a binary body, keeping the header the server used to name the file.
  Future<({List<int> bytes, String? contentDisposition})> download(String path) async {
    try {
      final response = await dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return (
        bytes: response.data ?? const <int>[],
        contentDisposition: response.headers.value('content-disposition'),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> delete(String path) async {
    await _send(() => dio.delete<dynamic>(path));
  }

  /// A DELETE that answers with a body — a bulk clear reports how much it removed,
  /// which 204 has no way to say.
  Future<T> deleteWithResult<T>(String path) => _send(() => dio.delete<T>(path));

  Future<T> _send<T>(Future<Response<T>> Function() request) async {
    try {
      final response = await request();
      return response.data as T;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
