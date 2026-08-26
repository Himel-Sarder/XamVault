import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/providers.dart';

enum AuthStatus {
  /// Start-up: secure storage has not been read yet, so we do not know.
  unknown,
  unauthenticated,
  authenticated,
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isBusy = false,
    this.errorMessage,
  });

  final AuthStatus status;
  final User? user;
  final bool isBusy;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
  bool get isResolved => status != AuthStatus.unknown;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    bool? isBusy,
    String? errorMessage,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      isBusy: isBusy ?? this.isBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Owns the session. Every routing decision reads from here.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  /// Called once at start-up: restores a persisted session and confirms it is still
  /// valid with the server, because a token can be revoked while the app was closed.
  Future<void> restoreSession() async {
    final tokens = ref.read(tokenManagerProvider);
    await tokens.restore();

    if (!tokens.hasSession) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final user = await ref.read(authRepositoryProvider).me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException {
      await tokens.clear();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login({required String userId, required String password}) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final repository = ref.read(authRepositoryProvider);
      final result = await repository.login(userId: userId, password: password);
      await ref.read(tokenManagerProvider).save(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
          );
      // The login response carries only the compact user (id, user_id, name, role).
      // Fetch /auth/me so the session always holds the full record - department and
      // role profile included - instead of a half-populated one that only fills in
      // after the next app restart.
      final user = await repository.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } on ApiException catch (error) {
      // Covers both a rejected credential and a session that could not be completed;
      // either way no partial session is left behind.
      await ref.read(tokenManagerProvider).clear();
      state = AuthState(
        status: AuthStatus.unauthenticated,
        isBusy: false,
        errorMessage: error.message,
      );
      return false;
    }
  }

  Future<void> logout() async {
    final tokens = ref.read(tokenManagerProvider);
    final refreshToken = tokens.refreshToken;
    if (refreshToken != null) {
      try {
        await ref.read(authRepositoryProvider).logout(refreshToken);
      } on ApiException {
        // The server may be unreachable; the local session still goes away.
      }
    }
    await tokens.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Invoked by [AuthInterceptor] when refreshing failed and the session is unrecoverable.
  Future<void> handleSessionExpired() async {
    await ref.read(tokenManagerProvider).clear();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      errorMessage: 'Your session has expired. Please sign in again.',
    );
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
