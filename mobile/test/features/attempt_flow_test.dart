import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/features/student/exam_attempt_screen.dart';
import 'package:uniexam/features/student/widgets/exam_timer.dart';
import 'package:uniexam/models/attempt.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeStudentRepository student}) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(student),
      // In a widget test `defaultTargetPlatform` is Android, so the real bridge would
      // reach for a platform channel that does not exist here.
      examSecurityProvider.overrideWithValue(FakeExamSecurity()),
    ],
    child: MaterialApp(home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('countdown formatting', () {
    test('renders minutes and seconds, and hours only when needed', () {
      expect(formatCountdown(0), '00:00');
      expect(formatCountdown(59), '00:59');
      expect(formatCountdown(90), '01:30');
      expect(formatCountdown(1478), '24:38');
      expect(formatCountdown(3661), '1:01:01');
    });

    test('never shows a negative time', () {
      expect(formatCountdown(-10), '00:00');
    });
  });

  group('exam screen', () {
    testWidgets('shows the first question and the server countdown', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()..currentAttempt = buildAttempt(remainingSeconds: 1478);

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      expect(find.text('Question 1 of 3'), findsOneWidget);
      expect(find.textContaining('Question 1: what is normalization?'), findsWidgets);
      expect(find.text('24:38'), findsOneWidget);
      expect(find.textContaining('0/3 answered'), findsOneWidget);
    });

    testWidgets('selecting an option saves it and updates the count', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()..currentAttempt = buildAttempt();

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      final optionId = student.currentAttempt!.questions.first.options[1].id;
      await tester.tap(find.byKey(Key('option_$optionId')));
      await tester.pumpAndSettle();

      expect(student.savedAnswers, hasLength(1));
      expect(student.savedAnswers.single.optionId, optionId);
      expect(find.textContaining('1/3 answered'), findsOneWidget);
    });

    testWidgets('tapping the chosen option again clears it', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()..currentAttempt = buildAttempt();

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      final optionId = student.currentAttempt!.questions.first.options[0].id;
      await tester.tap(find.byKey(Key('option_$optionId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('option_$optionId')));
      await tester.pumpAndSettle();

      expect(student.savedAnswers.map((entry) => entry.optionId).toList(), [optionId, null]);
      expect(find.textContaining('0/3 answered'), findsOneWidget);
    });

    testWidgets('next and previous move through the paper', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()..currentAttempt = buildAttempt();

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('next_question')));
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('previous_question')));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 of 3'), findsOneWidget);
    });

    testWidgets('the palette jumps straight to a question', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()..currentAttempt = buildAttempt();

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('palette_3')));
      await tester.pumpAndSettle();

      expect(find.text('Question 3 of 3'), findsOneWidget);
      // ...and the far edges of the paper disable the arrows.
      final next = tester.widget<FilledButton>(find.byKey(const Key('next_question')));
      expect(next.onPressed, isNull);
    });

    testWidgets('back navigation is blocked when the teacher turned it off',
        (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(allowBackNavigation: false);

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('next_question')));
      await tester.pumpAndSettle();

      final previous =
          tester.widget<OutlinedButton>(find.byKey(const Key('previous_question')));
      expect(previous.onPressed, isNull, reason: 'the exam forbids going back');
    });
  });

  group('submission', () {
    testWidgets('the confirmation counts what is answered and what is not',
        (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(answers: const {100: 1000});

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_exam')));
      await tester.pumpAndSettle();

      expect(find.text('Submit this exam?'), findsOneWidget);
      expect(find.text('Answered: 1 / 3'), findsOneWidget);
      expect(find.text('Unanswered: 2'), findsOneWidget);
      expect(find.textContaining('cannot change your answers'), findsOneWidget);
    });

    testWidgets('keeping working does not submit', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()..currentAttempt = buildAttempt();

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_exam')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep working'));
      await tester.pumpAndSettle();

      expect(student.submitCalls, 0);
      expect(find.text('Question 1 of 3'), findsOneWidget);
    });

    testWidgets('confirming submits and shows the closing screen', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()..currentAttempt = buildAttempt();

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_exam')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(student.submitCalls, 1);
      expect(find.text('Exam submitted'), findsOneWidget);
      expect(find.textContaining('once your teacher releases'), findsOneWidget);
      // The exam controls are gone: there is nothing left to change.
      expect(find.byKey(const Key('submit_exam')), findsNothing);
    });

    testWidgets('an already-submitted attempt opens straight into the closing screen',
        (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(status: AttemptStatus.autoSubmitted, remainingSeconds: 0);

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      expect(find.text('Time is up'), findsOneWidget);
      expect(find.textContaining('submitted automatically'), findsOneWidget);
      expect(find.byKey(const Key('option_1000')), findsNothing);
    });
  });

  group('written answers', () {
    testWidgets('a short answer question shows a writing area, not options',
        (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(questionCount: 1, writtenTypes: {0: 'SHORT_ANSWER'});

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('short_answer_field')), findsOneWidget);
      expect(find.byKey(const Key('option_1000')), findsNothing);
    });

    testWidgets('typing is saved once, after a pause', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(questionCount: 1, writtenTypes: {0: 'SHORT_ANSWER'});

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('short_answer_field')), 'TCP is reliable');
      await tester.pump(const Duration(milliseconds: 200));
      // Still typing: nothing sent yet.
      expect(student.savedTexts, isEmpty);

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(student.savedTexts, hasLength(1));
      expect(student.savedTexts.single.text, 'TCP is reliable');
    });

    testWidgets('a code question shows the editor and its limits', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(questionCount: 1, writtenTypes: {0: 'CODE_ANSWER'});

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('code_answer_field')), findsOneWidget);
      expect(find.text('CPP'), findsOneWidget);
      expect(find.text('2s time limit'), findsOneWidget);
      expect(find.textContaining('marks this answer after the exam'), findsOneWidget);
    });

    testWidgets('an unsent keystroke is flushed before submitting', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(questionCount: 1, writtenTypes: {0: 'SHORT_ANSWER'});

      await tester.pumpWidget(wrap(const ExamAttemptScreen(attemptId: 900), student: student));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('short_answer_field')), 'Last thought');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('submit_exam')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      // Nothing typed is lost just because the pause was short.
      expect(student.savedTexts.map((entry) => entry.text), contains('Last thought'));
      expect(student.submitCalls, 1);
    });
  });
}
