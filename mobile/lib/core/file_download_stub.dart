import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a saved file ended up.
class SavedFile {
  const SavedFile({required this.location, this.uri});

  /// Shown to a person: "Downloads/CSE-301-results.pdf".
  final String location;

  /// A `content://` URI to hand back to the platform, when there is one. Absent on
  /// older Android, where the file goes to app storage that nothing else can open.
  final String? uri;

  bool get canOpen => uri != null;
}

const _channel = MethodChannel('com.uniexam/file_export');

/// Pretends the platform can save, so the channel contract can be tested.
///
/// `dart:io`'s [Platform] reports the *host* OS under `flutter test`, so a bare
/// `Platform.isAndroid` guard would refuse every call on a developer's machine and
/// leave this file with no tests at all -- which is how it stayed a throwing stub for
/// so long without anyone noticing.
@visibleForTesting
bool debugPretendPlatformCanSave = false;

bool get _canSave => debugPretendPlatformCanSave || Platform.isAndroid;

/// Saves a downloaded report where the person can find it again.
///
/// The bytes are already in memory: a report sits behind the caller's bearer token, so
/// it is fetched first and handed here. On Android this writes into Downloads through
/// MediaStore, which needs no storage permission.
///
/// This used to throw [UnsupportedError] on every platform but web, which meant every
/// export on a phone -- the platform the app is actually for -- ended in "saving is not
/// available on this platform yet".
Future<SavedFile> saveFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) async {
  if (!_canSave) {
    throw UnsupportedError('Saving files is not available on this platform yet');
  }

  try {
    final result = await _channel.invokeMapMethod<String, Object?>('save', {
      // Uint8List crosses the channel as bytes; a plain List<int> would be encoded one
      // integer at a time, which for a multi-megabyte spreadsheet is ruinous.
      'bytes': Uint8List.fromList(bytes),
      'filename': filename,
      'mimeType': mimeType,
    });
    return SavedFile(
      location: result?['location'] as String? ?? filename,
      uri: result?['uri'] as String?,
    );
  } on PlatformException catch (error) {
    throw FileSaveException(error.message ?? 'Could not save the file');
  } on MissingPluginException {
    // An older build of the app shell without the channel.
    throw FileSaveException('This version of the app cannot save files');
  }
}

/// Opens a file that [saveFile] just wrote. False if nothing can open it.
Future<bool> openSavedFile(SavedFile file, String mimeType) async {
  if (!file.canOpen || !_canSave) return false;
  try {
    return await _channel.invokeMethod<bool>('open', {
          'uri': file.uri,
          'mimeType': mimeType,
        }) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Saving failed for a reason worth showing a person.
class FileSaveException implements Exception {
  const FileSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
