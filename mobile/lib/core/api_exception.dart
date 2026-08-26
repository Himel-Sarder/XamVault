import 'dart:io';

import 'package:dio/dio.dart';

/// A transport-independent error the UI can render.
///
/// Screens never see a [DioException]; they see a message that is safe to show and a
/// status code they can branch on.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  /// True when the request never reached the server, so "retry" is the useful advice.
  bool get isNetworkError => statusCode == null;

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          'The server took too long to respond. Check your connection and try again.',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (error.error is SocketException || error.type == DioExceptionType.connectionError) {
          return const ApiException(
            'Cannot reach the server. Check your connection and the API address.',
          );
        }
        return ApiException(error.message ?? 'Something went wrong.');
      case DioExceptionType.cancel:
        return const ApiException('Request cancelled.');
      case DioExceptionType.badCertificate:
        return const ApiException('The server certificate could not be verified.');
      case DioExceptionType.badResponse:
        return ApiException.fromResponse(error.response);
    }
  }

  factory ApiException.fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final data = response?.data;

    String? detail;
    String? code;
    if (data is Map) {
      final rawDetail = data['detail'];
      if (rawDetail is String) {
        detail = rawDetail;
      } else if (rawDetail is List && rawDetail.isNotEmpty) {
        // FastAPI 422 payload: [{loc: [...], msg: "...", type: "..."}]
        final first = rawDetail.first;
        if (first is Map && first['msg'] is String) {
          detail = first['msg'] as String;
        }
      }
      if (data['code'] is String) code = data['code'] as String;
    }

    return ApiException(
      detail ?? _defaultMessageFor(status),
      statusCode: status,
      code: code,
    );
  }

  static String _defaultMessageFor(int? status) {
    switch (status) {
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'Not found.';
      case 409:
        return 'That conflicts with something that already exists.';
      case 429:
        return 'Too many attempts. Please wait a moment and try again.';
      case 500:
      case 502:
      case 503:
        return 'The server is having trouble. Please try again shortly.';
      default:
        return 'Something went wrong.';
    }
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
