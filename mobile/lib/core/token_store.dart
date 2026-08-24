import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where tokens live.
///
/// Abstracted so tests can swap in an in-memory store; production always uses the
/// platform keystore.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> deleteAll();
}

/// Backed by the Android Keystore / iOS Keychain via `flutter_secure_storage`.
///
/// Deliberately not `SharedPreferences`: that writes plaintext XML into the app's data
/// directory, readable by anyone with a rooted device or an `adb backup`.
class SecureTokenStore implements TokenStore {
  /// `flutter_secure_storage` 11 defaults to AES-GCM data encryption with an
  /// RSA-OAEP key wrapped by the Android Keystore, so no extra options are needed.
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Non-persistent store used by tests.
class InMemoryTokenStore implements TokenStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> deleteAll() async => _values.clear();
}
