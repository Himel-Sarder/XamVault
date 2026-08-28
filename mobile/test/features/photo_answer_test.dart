import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/student/widgets/photo_answer_field.dart';

Widget wrap({
  required List<String> urls,
  bool busy = false,
  VoidCallback? onCapture,
  void Function(String)? onRemove,
}) =>
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PhotoAnswerField(
            urls: urls,
            maxPhotos: 3,
            busy: busy,
            onCapture: onCapture ?? () {},
            onRemove: onRemove ?? (_) {},
          ),
        ),
      ),
    );

void main() {
  group('before any photograph', () {
    testWidgets('it says what to do rather than only offering a button',
        (tester) async {
      await tester.pumpWidget(wrap(urls: const []));
      await tester.pump();

      expect(find.textContaining('Answer on paper, then photograph it'), findsOneWidget);
      expect(find.textContaining('Up to 3 photos'), findsOneWidget);
      expect(find.text('Open camera'), findsOneWidget);
    });

    testWidgets('tapping opens the camera', (tester) async {
      var opened = 0;
      await tester.pumpWidget(wrap(urls: const [], onCapture: () => opened++));
      await tester.pump();

      await tester.tap(find.byKey(const Key('capture_photo')));
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('with photographs added', () {
    testWidgets('it counts them against the limit', (tester) async {
      await tester.pumpWidget(wrap(urls: const ['/uploads/a.png', '/uploads/b.png']));
      await tester.pump();

      expect(find.text('2 of 3 photos added'), findsOneWidget);
      expect(find.text('Add another photo'), findsOneWidget);
    });

    testWidgets('each one can be removed', (tester) async {
      String? removed;
      await tester.pumpWidget(wrap(
        urls: const ['/uploads/a.png', '/uploads/b.png'],
        onRemove: (url) => removed = url,
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('remove_photo_1')));
      await tester.pump();
      expect(removed, '/uploads/b.png');
    });

    testWidgets('at the limit the button explains itself rather than going dead',
        (tester) async {
      await tester.pumpWidget(wrap(
        urls: const ['/uploads/a.png', '/uploads/b.png', '/uploads/c.png'],
      ));
      await tester.pump();

      expect(find.text('All 3 photos added'), findsOneWidget);
      expect(find.text('Remove one to take a different photo.'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('All 3 photos added'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('while uploading', () {
    testWidgets('it says so instead of appearing broken', (tester) async {
      await tester.pumpWidget(wrap(urls: const ['/uploads/a.png'], busy: true));
      await tester.pump();

      expect(find.text('Uploading...'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Uploading...'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('removal is held back too, so two writes cannot race', (tester) async {
      var removals = 0;
      await tester.pumpWidget(wrap(
        urls: const ['/uploads/a.png'],
        busy: true,
        onRemove: (_) => removals++,
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('remove_photo_0')));
      await tester.pump();
      expect(removals, 0);
    });
  });
}
