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

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _api.post<dynamic>(
        '/auth/change-password',
        data: {'current_password': currentPassword, 'new_password': newPassword},
      );
}
