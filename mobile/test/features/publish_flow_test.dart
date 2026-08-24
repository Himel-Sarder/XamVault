import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/features/teacher/exam_detail_screen.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeExamRepository exams}) {
  return ProviderScope(
    overrides: [
      examRepositoryProvider.overrideWithValue(exams),
      courseRepositoryProvider.overrideWithValue(FakeCourseRepository()),
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
  testWidgets('an exam that is not ready shows the reasons and blocks publishing',
      (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository(
      exams: [buildExam(id: 10)],
      publishCheckResult: const PublishCheck(
        canPublish: false,
        issues: [
          PublishIssue(field: 'questions', message: 'Add at least one question before publishing'),
          PublishIssue(field: 'start_at', message: 'Set the date and time the exam starts'),
        ],
      ),
    );
    await tester.pumpWidget(wrap(const ExamDetailScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Not ready to publish'), findsOneWidget);
    expect(find.textContaining('Add at least one question'), findsOneWidget);
    expect(find.textContaining('Set the date and time'), findsOneWidget);

    // The key sits on the button itself, so read it directly.
    final button = tester.widget<FilledButton>(find.byKey(const Key('publish_exam')));
    expect(button.onPressed, isNull, reason: 'publishing must be blocked');
  });

  testWidgets('publishing asks for confirmation first', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository(
      exams: [buildExam(id: 10, questionCount: 1, totalMarks: 5)],
      questions: [buildExamQuestion(examId: 10, marks: 5)],
    );
    await tester.pumpWidget(wrap(const ExamDetailScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('publish_exam')));
    await tester.pumpAndSettle();
    expect(find.text('Publish this exam?'), findsOneWidget);
    expect(find.textContaining('questions are frozen'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(exams.publishCalls, 0);

    await tester.tap(find.byKey(const Key('publish_exam')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();
    expect(exams.publishCalls, 1);
  });

  testWidgets('the teacher view marks which option is the answer', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository(
      exams: [buildExam(id: 10, questionCount: 1)],
      questions: [
        buildExamQuestion(
          examId: 10,
          text: 'Which is a NoSQL database?',
          options: const ['MySQL', 'MongoDB'],
          correctIndex: 1,
        ),
      ],
    );
    await tester.pumpWidget(wrap(const ExamDetailScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Which is a NoSQL database?'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  testWidgets('a published exam offers no editing affordances', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository(
      exams: [buildExam(id: 10, status: ExamStatus.published, questionCount: 1)],
      questions: [buildExamQuestion(examId: 10, isFrozen: true)],
    );
    await tester.pumpWidget(wrap(const ExamDetailScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add_question_fab')), findsNothing);
    expect(find.byKey(const Key('edit_exam')), findsNothing);
    expect(find.byKey(const Key('publish_exam')), findsNothing);
    expect(find.byKey(const Key('question_menu_100')), findsNothing);
    expect(find.text('Frozen'), findsOneWidget);
    expect(find.textContaining('questions are frozen'), findsOneWidget);
  });

  testWidgets('the settings summary reflects what was configured', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository(
      exams: [
        buildExam(
          id: 10,
          settings: const ExamSettings(shuffleQuestions: true, maxAttempts: 3),
        ),
      ],
    );
    await tester.pumpWidget(wrap(const ExamDetailScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Shuffle questions'), findsOneWidget);
    expect(find.text('Maximum attempts: 3'), findsOneWidget);
  });
}
