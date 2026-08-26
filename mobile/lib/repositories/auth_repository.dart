import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/auth_tokens.dart';
import 'package:uniexam/models/user.dart';

/// Everything the app can ask the backend about the current identity.
class AuthRepository {
  const AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthTokens> login({required String userId, required String password}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'user_id': userId, 'password': password},
    );
    return AuthTokens.fromJson(data);
  }

  Future<User> me() async {
    final data = await _api.get<Map<String, dynamic>>('/auth/me');
    return User.fromJson(data);
  }

  /// Revokes the refresh token server-side. Failures are the caller's to ignore: the
  /// local session is cleared either way.
  Future<void> logout(String refreshToken) =>
      _api.post<dynamic>('/auth/logout', data: {'refresh_token': refreshToken});

  /// Nudges the server awake without caring whether it answers.
  ///
  /// A free host sleeps; this starts the wake while the user is still reading the
  /// splash or typing a password, so the cold start overlaps with something they were
  /// doing anyway. Failure is genuinely uninteresting — the real request will report
  /// anything that matters.
  Future<void> warmUp() async {
    try {
      // Absolute URL: /health sits at the server root, outside the /api/v1 prefix.
      await _api.get<dynamic>(AppConfig.healthUrl);
    } catch (_) {
      // Deliberately swallowed: this is a nudge, not a check.
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _api.post<dynamic>(
        '/auth/change-password',
        data: {'current_password': currentPassword, 'new_password': newPassword},
      );
}
