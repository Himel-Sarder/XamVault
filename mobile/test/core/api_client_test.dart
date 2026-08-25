import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/token_manager.dart';
import 'package:uniexam/core/token_store.dart';

import 'fake_adapter.dart';

const _baseUrl = 'http://test.local/api/v1';

typedef Harness = ({
  ApiClient client,
  FakeAdapter api,
  FakeAdapter refresh,
  TokenManager tokens,
  List<String> events,
});

Harness buildClient({
  required Future<ResponseBody> Function(RequestOptions) onApiCall,
  required Future<ResponseBody> Function(RequestOptions) onRefreshCall,
}) {
  final tokens = TokenManager(InMemoryTokenStore());
  final events = <String>[];

  final apiAdapter = FakeAdapter(onApiCall);
  final refreshAdapter = FakeAdapter(onRefreshCall);

  final inner = Dio()..httpClientAdapter = apiAdapter;
  final refreshDio = Dio()..httpClientAdapter = refreshAdapter;

  final client = ApiClient(
    tokenManager: tokens,
    baseUrl: _baseUrl,
    inner: inner,
    refreshClient: refreshDio,
    onSessionExpired: () async => events.add('session_expired'),
  );

  return (
    client: client,
    api: apiAdapter,
    refresh: refreshAdapter,
    tokens: tokens,
    events: events,
  );
}

void main() {
  test('attaches the access token to authenticated requests', () async {
    final harness = buildClient(
      onApiCall: (_) async => jsonResponse({'ok': true}),
      onRefreshCall: (_) async => jsonResponse({}, statusCode: 500),
    );
    await harness.tokens.save(accessToken: 'access-1', refreshToken: 'refresh-1');

    await harness.client.get<Map<String, dynamic>>('/courses');

    expect(harness.api.requests.single.headers['Authorization'], 'Bearer access-1');
  });

  test('does not attach a token to the login request', () async {
    final harness = buildClient(
      onApiCall: (_) async => jsonResponse({'access_token': 'x'}),
      onRefreshCall: (_) async => jsonResponse({}, statusCode: 500),
    );
    await harness.tokens.save(accessToken: 'access-1', refreshToken: 'refresh-1');

    await harness.client.post<Map<String, dynamic>>('/auth/login', data: {});

    expect(harness.api.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('a 401 triggers a refresh and the original request is replayed', () async {
    var apiCalls = 0;
    final harness = buildClient(
      onApiCall: (options) async {
        apiCalls++;
        if (apiCalls == 1) {
          return jsonResponse({'detail': 'Token has expired'}, statusCode: 401);
        }
        expect(options.headers['Authorization'], 'Bearer access-2');
        return jsonResponse({'items': <dynamic>[], 'total': 0});
      },
      onRefreshCall: (_) async => jsonResponse(refreshPayload()),
    );
    await harness.tokens.save(accessToken: 'access-1', refreshToken: 'refresh-1');

    final result = await harness.client.get<Map<String, dynamic>>('/courses');

    expect(result['total'], 0);
    expect(apiCalls, 2, reason: 'the request should be retried exactly once');
    expect(harness.tokens.accessToken, 'access-2');
    expect(harness.tokens.refreshToken, 'refresh-2', reason: 'rotation must be stored');
    expect(harness.events, isEmpty);
  });

  test('a failed refresh reports the session as expired', () async {
    final harness = buildClient(
      onApiCall: (_) async => jsonResponse({'detail': 'expired'}, statusCode: 401),
      onRefreshCall: (_) async => jsonResponse({'detail': 'revoked'}, statusCode: 401),
    );
    await harness.tokens.save(accessToken: 'access-1', refreshToken: 'refresh-1');

    await expectLater(
      harness.client.get<Map<String, dynamic>>('/courses'),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
    );
    expect(harness.events, ['session_expired']);
  });

  test('concurrent 401s share a single refresh', () async {
    // The server rotates refresh tokens, so a second concurrent refresh would present an
    // already-revoked token and log the user out. The interceptor must coalesce them.
    var refreshCalls = 0;
    final seenTokens = <String>[];

    final harness = buildClient(
      onApiCall: (options) async {
        final auth = options.headers['Authorization'] as String;
        seenTokens.add(auth);
        if (auth == 'Bearer access-1') {
          return jsonResponse({'detail': 'expired'}, statusCode: 401);
        }
        return jsonResponse({'ok': true});
      },
      onRefreshCall: (_) async {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonResponse(refreshPayload());
      },
    );
    await harness.tokens.save(accessToken: 'access-1', refreshToken: 'refresh-1');

    await Future.wait([
      harness.client.get<Map<String, dynamic>>('/courses'),
      harness.client.get<Map<String, dynamic>>('/departments'),
      harness.client.get<Map<String, dynamic>>('/users/me'),
    ]);

    expect(refreshCalls, 1);
    expect(seenTokens.where((token) => token == 'Bearer access-2').length, 3);
  });

  test('a 401 without a stored refresh token does not attempt a refresh', () async {
    final harness = buildClient(
      onApiCall: (_) async => jsonResponse({'detail': 'Not authenticated'}, statusCode: 401),
      onRefreshCall: (_) async => fail('refresh must not be attempted'),
    );

    await expectLater(
      harness.client.get<Map<String, dynamic>>('/courses'),
      throwsA(isA<ApiException>()),
    );
    expect(harness.refresh.requests, isEmpty);
    expect(harness.events, ['session_expired']);
  });

  test('non-401 errors surface as ApiException without refreshing', () async {
    final harness = buildClient(
      onApiCall: (_) async => jsonResponse(
        {'detail': 'You do not have permission to do that.', 'code': 'permission_denied'},
        statusCode: 403,
      ),
      onRefreshCall: (_) async => fail('refresh must not be attempted'),
    );
    await harness.tokens.save(accessToken: 'access-1', refreshToken: 'refresh-1');

    await expectLater(
      harness.client.get<Map<String, dynamic>>('/courses'),
      throwsA(isA<ApiException>()
          .having((e) => e.isForbidden, 'isForbidden', isTrue)
          .having((e) => e.code, 'code', 'permission_denied')),
    );
  });

  test('a FastAPI 422 validation body is turned into a readable message', () async {
    final harness = buildClient(
      onApiCall: (_) async => jsonResponse({
        'detail': [
          {'loc': ['body', 'new_password'], 'msg': 'String should have at least 8 characters'}
        ]
      }, statusCode: 422),
      onRefreshCall: (_) async => fail('refresh must not be attempted'),
    );

    await expectLater(
      harness.client.post<Map<String, dynamic>>('/auth/change-password', data: {}),
      throwsA(isA<ApiException>().having(
        (e) => e.message,
        'message',
        contains('at least 8 characters'),
      )),
    );
  });
}
