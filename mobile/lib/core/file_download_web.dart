import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hands the bytes to the browser as a download.
///
/// The file is already in memory — it was fetched with the caller's bearer token, which
/// a plain `<a href>` to the API could not have carried.
Future<void> saveFile({
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
}
