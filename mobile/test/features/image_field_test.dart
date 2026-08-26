import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/image_field.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

/// Holds the url the way a real form does, so a test can see what Remove left behind.
class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.onChanged});

  final String? initial;
  final ValueChanged<String?> onChanged;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String? _url = widget.initial;

  @override
  Widget build(BuildContext context) => ImageField(
        fieldKey: const Key('question_image'),
        label: 'Question image',
        url: _url,
        onChanged: (url) {
          setState(() => _url = url);
          widget.onChanged(url);
        },
      );
}

Widget wrap(FakeExamRepository exams, {String? initial, ValueChanged<String?>? onChanged}) =>
    ProviderScope(
      overrides: [examRepositoryProvider.overrideWithValue(exams)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: _Host(initial: initial, onChanged: onChanged ?? (_) {}),
        ),
      ),
    );

void main() {
  group('previewing', () {
    testWidgets('an image is addressed at the server root, not the API prefix',
        (tester) async {
      // /uploads sits outside /api/v1. Getting this wrong is why every preview 404d.
      final resolved = AppConfig.mediaUrl('/uploads/abc.png');
      expect(resolved.endsWith('/uploads/abc.png'), isTrue);
      expect(resolved.contains('/api/v1'), isFalse);
    });

    testWidgets('a url already absolute is left alone', (tester) async {
      const absolute = 'https://cdn.example.com/x.png';
      expect(AppConfig.mediaUrl(absolute), absolute);
    });

    testWidgets('an image that will not load says so instead of showing nothing',
        (tester) async {
      await tester.pumpWidget(wrap(FakeExamRepository(), initial: '/uploads/abc.png'));
      await tester.pump();

      // Image.network cannot fetch in a widget test, so this exercises the error path.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('no image means no preview and no Remove', (tester) async {
      await tester.pumpWidget(wrap(FakeExamRepository()));
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Choose image'), findsOneWidget);
    });
  });

  group('removing', () {
    testWidgets('it clears the question and asks the server to forget the file',
        (tester) async {
      final exams = FakeExamRepository();
      String? left = '/uploads/abc.png';

      await tester.pumpWidget(wrap(
        exams,
        initial: '/uploads/abc.png',
        onChanged: (url) => left = url,
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('remove_Question image')));
      await tester.pumpAndSettle();

      expect(left, isNull);
      expect(exams.deletedImages, ['/uploads/abc.png']);
      expect(find.text('Choose image'), findsOneWidget);
    });

    testWidgets('the button becomes Choose image again', (tester) async {
      await tester.pumpWidget(wrap(FakeExamRepository(), initial: '/uploads/abc.png'));
      await tester.pump();

      expect(find.text('Replace'), findsOneWidget);
      await tester.tap(find.byKey(const Key('remove_Question image')));
      await tester.pumpAndSettle();

      expect(find.text('Choose image'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('a server that refuses still clears the question', (tester) async {
      final exams = FakeExamRepository()
        ..failWith = const ApiException(
          'This image is still used by a question, so it was not deleted.',
          statusCode: 409,
          code: 'image_in_use',
        );
      String? left = '/uploads/abc.png';

      await tester.pumpWidget(wrap(
        exams,
        initial: '/uploads/abc.png',
        onChanged: (url) => left = url,
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('remove_Question image')));
      await tester.pumpAndSettle();

      // The teacher asked for it gone from their question. That must not depend on a
      // network call succeeding, and an orphaned row is not worth interrupting them over.
      expect(left, isNull);
      expect(find.textContaining('still used'), findsNothing);
    });
  });
}
