import 'package:uniexam/core/token_store.dart';

/// Holds the current token pair.
///
/// Reads are served from memory (the interceptor touches this on every request) while
/// writes go through to secure storage so a restart restores the session.
class TokenManager {
  TokenManager(this._store);

  static const _accessKey = 'uniexam.access_token';
  static const _refreshKey = 'uniexam.refresh_token';

  final TokenStore _store;

  String? _accessToken;
  String? _refreshToken;
  bool _loaded = false;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get hasSession => _refreshToken != null;

  /// Loads persisted tokens once at start-up.
  Future<void> restore() async {
    if (_loaded) return;
    _accessToken = await _store.read(_accessKey);
    _refreshToken = await _store.read(_refreshKey);
    _loaded = true;
  }

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _loaded = true;
    await _store.write(_accessKey, accessToken);
    await _store.write(_refreshKey, refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _loaded = true;
    await _store.deleteAll();
  }
}
