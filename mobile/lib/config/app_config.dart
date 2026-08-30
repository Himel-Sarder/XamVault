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

  /// The server root, without the versioned API prefix.
  ///
  /// Two things live outside `/api/v1`: uploaded files, which the API returns as paths
  /// like `/uploads/abc.png`, and `/health`.
  static String get serverRoot {
    const suffix = '/api/v1';
    return apiBaseUrl.endsWith(suffix)
        ? apiBaseUrl.substring(0, apiBaseUrl.length - suffix.length)
        : apiBaseUrl;
  }

  /// Where uploaded images live.
  static String get mediaBaseUrl => serverRoot;

  /// Cheap endpoint used to wake a sleeping host.
  static String get healthUrl => '$serverRoot/health';

  /// Turns a server-relative upload path into something an Image widget can load.
  static String mediaUrl(String path) =>
      path.startsWith('http') ? path : '$mediaBaseUrl$path';

  /// Sized for a host that sleeps.
  ///
  /// These were 15s and 20s, which is generous for a server already running and
  /// impossible for one that is not: a free Render instance spins down after about
  /// fifteen minutes idle and takes roughly forty seconds to come back, so the first
  /// request after a quiet spell timed out *every time* and reported itself as
  /// "cannot reach the server" — blaming the network for a wait that was expected.
  ///
  /// A minute and a half covers a cold start with room to spare. The cost of the longer
  /// ceiling is paid only by requests that were going to fail anyway, and the screens
  /// say what is happening rather than leaving a silent spinner (see [wakeHint]).
  static const Duration connectTimeout = Duration(seconds: 90);
  static const Duration receiveTimeout = Duration(seconds: 90);

  /// How long to wait before admitting the server is probably asleep.
  ///
  /// Short enough that a real cold start is explained early, long enough that a normal
  /// request never shows the message at all.
  static const Duration wakeHintAfter = Duration(seconds: 6);

  static const String wakeHint =
      'Waking the server. The first request after a quiet spell can take up to a minute.';

  /// The name on the launcher, the task switcher and the sign-in screen.
  ///
  /// The Dart package is still `uniexam` and the Android applicationId is still
  /// `com.uniexam.uniexam`. Neither is user-visible, and changing the latter would
  /// make this install as a second app rather than an update to the first.
  static const String appName = 'XamVault';

  /// The logo, as one constant so no screen hardcodes the path.
  static const String logoAsset = 'assets/logo-xamv.png';
}
