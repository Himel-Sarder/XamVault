
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/core/file_download.dart';

const _channel = MethodChannel('com.uniexam/file_export');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    // The suite runs on the host OS, not Android; this is what makes the channel
    // contract testable at all.
    debugPretendPlatformCanSave = true;
  });

  tearDown(() {
    debugPretendPlatformCanSave = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('saving a report', () {
    test('it reports the folder and name the file actually got', () async {
      // MediaStore renames on collision, so the name asked for is not always the name
      // written; the caller shows what came back, not what it sent.
      answerWith((_) async => <String, Object?>{
            'uri': 'content://media/external/downloads/42',
            'location': 'Downloads/CSE-301-results (1).pdf',
          });

      final saved = await saveFile(
        bytes: const [1, 2, 3],
        filename: 'CSE-301-results.pdf',
        mimeType: 'application/pdf',
      );

      expect(saved.location, 'Downloads/CSE-301-results (1).pdf');
      expect(saved.canOpen, isTrue);
    });

    test('the bytes cross as bytes, not as a list of integers', () async {
      // A multi-megabyte spreadsheet encoded one integer at a time is ruinous, and the
      // difference is invisible until someone exports a real cohort.
      answerWith((_) async => <String, Object?>{'uri': null, 'location': 'x.pdf'});

      await saveFile(bytes: const [1, 2, 3], filename: 'x.pdf', mimeType: 'application/pdf');

      expect(calls.single.arguments['bytes'], isA<Uint8List>());
    });

    test('a file with nowhere to open it says so', () async {
      // Older Android: the file lands in app storage that nothing else can read.
      answerWith((_) async => <String, Object?>{
            'uri': null,
            'location': '/storage/emulated/0/Android/data/.../report.pdf',
          });

      final saved = await saveFile(
        bytes: const [1],
        filename: 'report.pdf',
        mimeType: 'application/pdf',
      );

      expect(saved.canOpen, isFalse);
    });

    test('a platform failure becomes a sentence, not a stack trace', () async {
      answerWith((_) async => throw PlatformException(
            code: 'save_failed',
            message: 'Downloads folder is not available',
          ));

      expect(
        () => saveFile(bytes: const [1], filename: 'a.pdf', mimeType: 'application/pdf'),
        throwsA(isA<FileSaveException>().having(
          (e) => e.message,
          'message',
          'Downloads folder is not available',
        )),
      );
    });

    test('an app shell without the channel does not crash the export', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);

      expect(
        () => saveFile(bytes: const [1], filename: 'a.pdf', mimeType: 'application/pdf'),
        throwsA(isA<FileSaveException>()),
      );
    });
  });

  group('opening what was saved', () {
    test('it passes the uri and type through', () async {
      answerWith((_) async => true);

      const saved = SavedFile(location: 'Downloads/a.pdf', uri: 'content://x/1');
      expect(await openSavedFile(saved, 'application/pdf'), isTrue);
      expect(calls.single.method, 'open');
      expect(calls.single.arguments['uri'], 'content://x/1');
    });

    test('nothing to open is false rather than an error', () async {
      answerWith((_) async => false);

      const saved = SavedFile(location: '/data/a.pdf');
      expect(await openSavedFile(saved, 'application/pdf'), isFalse);
      // Never reached the platform: there was no uri to open.
      expect(calls, isEmpty);
    });

    test('no viewer installed is false, not a crash', () async {
      answerWith((_) async => throw PlatformException(code: 'no_activity'));

      const saved = SavedFile(location: 'Downloads/a.pdf', uri: 'content://x/1');
      expect(await openSavedFile(saved, 'application/pdf'), isFalse);
    });
  });
}
