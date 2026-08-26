import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/shared/notifications_screen.dart';
import 'package:uniexam/features/teacher/exam_detail_screen.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget wrapNotifications(FakeNotificationRepository notes) => ProviderScope(
      overrides: [notificationRepositoryProvider.overrideWithValue(notes)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const NotificationsScreen(),
      ),
    );

Widget wrapExam(FakeExamRepository exams) => ProviderScope(
      overrides: [examRepositoryProvider.overrideWithValue(exams)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ExamDetailScreen(examId: 10),
      ),
    );

Future<void> openMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const Key('exam_menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  group('removing a notification', () {
    testWidgets('swiping one away removes it', (tester) async {
      tall(tester);
      final notes = FakeNotificationRepository();
      final first = notes.notifications.first.id;

      await tester.pumpWidget(wrapNotifications(notes));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(Key('dismiss_$first')), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(notes.deleted, [first]);
    });

    testWidgets('clearing read asks first, and says what it will not touch',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(wrapNotifications(FakeNotificationRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clear_read')));
      await tester.pumpAndSettle();

      expect(find.text('Clear read notifications?'), findsOneWidget);
      // "Clear" could otherwise be read as "clear everything".
      expect(find.textContaining('not read yet is kept'), findsOneWidget);
      // And it must be clear this removes the notice, not the thing it announced.
      expect(find.textContaining('never the exam or result'), findsOneWidget);
    });

    testWidgets('cancelling the dialog clears nothing', (tester) async {
      tall(tester);
      final notes = FakeNotificationRepository();
      await tester.pumpWidget(wrapNotifications(notes));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clear_read')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(notes.clearReadCalls, 0);
    });
  });

  group('removing an exam', () {
    FakeExamRepository draft() => FakeExamRepository(
          exams: [buildExam(id: 10, status: ExamStatus.draft)],
        );

    FakeExamRepository published() => FakeExamRepository(
          exams: [buildExam(id: 10, status: ExamStatus.published)],
        );

    testWidgets('deleting asks first and warns it may be refused', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrapExam(draft()));
      await tester.pumpAndSettle();
      await openMenu(tester, 'Delete exam');

      expect(find.text('Delete this exam?'), findsOneWidget);
      expect(find.textContaining('stay in your bank'), findsOneWidget);
      // The teacher is told the possible outcome before committing to it.
      expect(find.textContaining('already sat it'), findsOneWidget);
    });

    testWidgets('a draft is deleted when confirmed', (tester) async {
      tall(tester);
      final exams = draft();
      await tester.pumpWidget(wrapExam(exams));
      await tester.pumpAndSettle();
      await openMenu(tester, 'Delete exam');

      await tester.tap(find.byKey(const Key('confirm_delete_exam')));
      await tester.pumpAndSettle();

      expect(exams.deletedExams, [10]);
    });

    testWidgets('keeping it deletes nothing', (tester) async {
      tall(tester);
      final exams = draft();
      await tester.pumpWidget(wrapExam(exams));
      await tester.pumpAndSettle();
      await openMenu(tester, 'Delete exam');

      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();

      expect(exams.deletedExams, isEmpty);
    });

    testWidgets('the refusal from the server is shown, not paraphrased',
        (tester) async {
      tall(tester);
      final exams = published()
        ..failDeleteWith = const ApiException(
          '3 students have already sat this exam, so deleting it would delete their '
          'answers and results. Cancel it instead.',
          statusCode: 409,
          code: 'exam_has_attempts',
        );
      await tester.pumpWidget(wrapExam(exams));
      await tester.pumpAndSettle();
      await openMenu(tester, 'Delete exam');

      await tester.tap(find.byKey(const Key('confirm_delete_exam')));
      await tester.pumpAndSettle();

      // Only the server knows how many sat it, so it does the explaining.
      expect(find.textContaining('3 students have already sat'), findsOneWidget);
      expect(find.textContaining('Cancel it instead'), findsOneWidget);
    });

    testWidgets('cancelling promises that nothing is lost', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrapExam(published()));
      await tester.pumpAndSettle();
      await openMenu(tester, 'Cancel exam');

      expect(find.textContaining('Nothing is lost'), findsOneWidget);
      expect(find.textContaining('remain readable'), findsOneWidget);
    });

    testWidgets('a draft is not offered cancel', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrapExam(draft()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exam_menu')));
      await tester.pumpAndSettle();

      // It never started, so there is nothing to stop — delete is the honest verb.
      expect(find.text('Delete exam'), findsOneWidget);
      expect(find.text('Cancel exam'), findsNothing);
    });
  });
}
