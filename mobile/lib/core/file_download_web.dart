import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Where a saved file ended up. The browser decides, so there is nothing to point at.
class SavedFile {
  const SavedFile({required this.location, this.uri});

  final String location;
  final String? uri;

  bool get canOpen => false;
}

/// Saving failed for a reason worth showing a person.
class FileSaveException implements Exception {
  const FileSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Hands the bytes to the browser as a download.
///
/// The file is already in memory — it was fetched with the caller's bearer token, which
/// a plain `<a href>` to the API could not have carried.
Future<SavedFile> saveFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) async {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // The blob would otherwise be held until the tab closes.
  web.URL.revokeObjectURL(url);
  // The browser puts it wherever it is configured to; naming a folder would be a guess.
  return SavedFile(location: filename);
}

/// Nothing to open: the browser has already taken the file.
Future<bool> openSavedFile(SavedFile file, String mimeType) async => false;
