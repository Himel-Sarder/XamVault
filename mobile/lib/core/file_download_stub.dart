/// Non-web fallback.
///
/// Saving a file on Android means a storage permission, a path, and a viewer to open it
/// with — none of which exists yet. Rather than pretend, the caller is told plainly.
Future<void> saveFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) async {
  throw UnsupportedError('Saving files is not available on this platform yet');
}
