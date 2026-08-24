import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A scriptable [HttpClientAdapter] so HTTP behaviour can be tested without a server.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object? body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// The shape of a successful /auth/refresh response.
Map<String, dynamic> refreshPayload({
  String accessToken = 'access-2',
  String refreshToken = 'refresh-2',
}) =>
    {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': 'bearer',
      'expires_in': 1800,
      'user': {'id': 1, 'user_id': 'u', 'name': 'n', 'role': 'student'},
    };
