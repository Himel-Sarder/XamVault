/// Build-time configuration.
///
/// The base URL is injected with `--dart-define` so one codebase targets the emulator,
/// a LAN device and Render without any source edit:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8000/api/v1
/// flutter build apk --dart-define=API_BASE_URL=https://uniexam-api.onrender.com/api/v1
/// ```
class AppConfig {
  const AppConfig._();

  /// 10.0.2.2 is the Android emulator's alias for the host machine's localhost.
  /// A physical device needs the host's LAN IP instead.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  /// Where uploaded images live. The API returns paths like `/uploads/abc.png`, which
  /// are relative to the server root rather than to the versioned API prefix.
  static String get mediaBaseUrl {
    const suffix = '/api/v1';
    return apiBaseUrl.endsWith(suffix)
        ? apiBaseUrl.substring(0, apiBaseUrl.length - suffix.length)
        : apiBaseUrl;
  }

  /// Turns a server-relative upload path into something an Image widget can load.
  static String mediaUrl(String path) =>
      path.startsWith('http') ? path : '$mediaBaseUrl$path';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  static const String appName = 'UniExam';
}
