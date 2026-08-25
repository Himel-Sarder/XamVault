import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/attempt_grading_screen.dart';
import 'package:uniexam/features/teacher/grading_queue_screen.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeExamRepository exams}) {
  return ProviderScope(
    overrides: [examRepositoryProvider.overrideWithValue(exams)],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('marking queue', () {
    testWidgets('shows who still needs marking', (tester) async {
      final exams = FakeExamRepository()
        ..queue = [
          buildGradingEntry(attemptId: 900, studentName: 'Alice', awaitingMarks: 2),
          buildGradingEntry(
            attemptId: 901,
            studentName: 'Bob',
            studentNumber: '20265678',
            awaitingMarks: 0,
            totalScore: 23,
          ),
        ];

      await tester.pumpWidget(wrap(const GradingQueueScreen(examId: 10), exams: exams));
      await tester.pumpAndSettle();

      expect(find.text('1 paper still to mark'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('2 to mark'), findsOneWidget);
      // A finished paper shows its score instead.
      expect(find.text('23/25'), findsOneWidget);
    });

    testWidgets('says when everything is marked', (tester) async {
      final exams = FakeExamRepository()
        ..queue = [buildGradingEntry(awaitingMarks: 0, totalScore: 23)];

      await tester.pumpWidget(wrap(const GradingQueueScreen(examId: 10), exams: exams));
      await tester.pumpAndSettle();

      expect(find.text('Everything is marked'), findsOneWidget);
    });

    testWidgets('says when nobody has submitted', (tester) async {
      await tester.pumpWidget(
        wrap(const GradingQueueScreen(examId: 10), exams: FakeExamRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No submissions yet'), findsOneWidget);
    });
  });

  group('marking one paper', () {
    testWidgets('shows the question and what the student wrote', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()..grading = buildAttemptGrading();

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      expect(find.text('Demo Student'), findsOneWidget);
      expect(find.textContaining('Explain the difference'), findsOneWidget);
      expect(find.textContaining('TCP is reliable'), findsOneWidget);
      expect(find.text('1 left'), findsOneWidget);
    });

    testWidgets('a code answer is shown verbatim', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()
        ..grading = buildAttemptGrading(answers: [
          buildAnswerToMark(
            type: 'CODE_ANSWER',
            language: 'cpp',
            questionText: 'Implement binary search.',
            answerText: 'int bsearch(int* a) { return 0; }',
          ),
        ]);

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('int bsearch'), findsOneWidget);
      expect(find.textContaining('code'), findsWidgets);
    });

    testWidgets('awarding marks sends them to the server', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()..grading = buildAttemptGrading();

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('marks_101')), '8');
      await tester.enterText(
        find.byKey(const Key('feedback_101')), 'Good, but mention ordering.');
      await tester.tap(find.byKey(const Key('save_marks_101')));
      await tester.pumpAndSettle();

      expect(exams.awarded, hasLength(1));
      expect(exams.awarded.single.marks, 8.0);
      expect(exams.awarded.single.feedback, 'Good, but mention ordering.');
    });

    testWidgets('marks above the maximum are refused before sending', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()..grading = buildAttemptGrading();

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('marks_101')), '50');
      await tester.tap(find.byKey(const Key('save_marks_101')));
      await tester.pumpAndSettle();

      expect(find.text('Marks must be between 0 and 10'), findsOneWidget);
      expect(exams.awarded, isEmpty);
    });

    testWidgets('a blank mark is refused', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()..grading = buildAttemptGrading();

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_marks_101')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a number of marks'), findsOneWidget);
      expect(exams.awarded, isEmpty);
    });

    testWidgets('an already-marked answer opens with its mark and offers an update',
        (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()
        ..grading = buildAttemptGrading(answers: [
          buildAnswerToMark(status: 'evaluated', marksAwarded: 8, feedback: 'Solid.'),
        ]);

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update marks'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      final marks = tester.widget<TextField>(find.byKey(const Key('marks_101')));
      expect(marks.controller?.text, '8');
    });

    testWidgets('an unanswered question says so', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()
        ..grading = buildAttemptGrading(answers: [buildAnswerToMark(answerText: null)]);

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not answered'), findsOneWidget);
    });

    testWidgets('a paper with no written questions needs no marking', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository()
        ..grading = buildAttemptGrading(answers: [], awaitingMarks: 0);

      await tester.pumpWidget(
        wrap(const AttemptGradingScreen(examId: 10, attemptId: 900), exams: exams),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing to mark'), findsOneWidget);
    });
  });
}
