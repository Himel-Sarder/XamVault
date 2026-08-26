/// Saves a downloaded file, however the current platform can.
///
/// Conditional export rather than a runtime `kIsWeb` check: `package:web` only compiles
/// for the web target, so an unconditional import would break the Android build.
library;

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
