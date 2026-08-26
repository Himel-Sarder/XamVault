import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/features/teacher/question_builder_screen.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeExamRepository exams}) {
  final router = GoRouter(
    initialLocation: '/builder',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('parent screen'))),
        routes: [GoRoute(path: 'builder', builder: (_, _) => child)],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      examRepositoryProvider.overrideWithValue(exams),
      courseRepositoryProvider.overrideWithValue(FakeCourseRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('starts with four blank options and the first marked correct',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('option_text_0')), findsOneWidget);
    expect(find.byKey(const Key('option_text_3')), findsOneWidget);
    expect(find.byKey(const Key('option_text_4')), findsNothing);
    // The type selector defaults to plain multiple choice.
    expect(find.byKey(const Key('question_type')), findsOneWidget);
    expect(find.text('Multiple choice'), findsWidgets);
  });

  testWidgets('will not submit an empty question', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();
    await tester.pumpWidget(
      wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: exams),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('question_save')));
    await tester.pumpAndSettle();

    expect(find.text('Write the question'), findsWidgets);
    expect(exams.addedQuestions, isEmpty);
  });

  testWidgets('rejects duplicate options before sending anything', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();
    await tester.pumpWidget(
      wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: exams),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('question_text')), 'Pick one');
    for (var index = 0; index < 4; index++) {
      await tester.enterText(find.byKey(Key('option_text_$index')), 'Same');
    }
    await tester.tap(find.byKey(const Key('question_save')));
    await tester.pumpAndSettle();

    expect(find.text('Options must be different from one another'), findsOneWidget);
    expect(exams.addedQuestions, isEmpty);
  });

  testWidgets('sends exactly one correct answer, the one the radio selects',
      (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();
    await tester.pumpWidget(
      wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: exams),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('question_text')),
      'What is the time complexity of binary search?',
    );
    await tester.enterText(find.byKey(const Key('question_marks')), '5');
    const labels = ['O(n)', 'O(log n)', 'O(n^2)', 'O(1)'];
    for (var index = 0; index < labels.length; index++) {
      await tester.enterText(find.byKey(Key('option_text_$index')), labels[index]);
    }
    await tester.tap(find.byKey(const Key('option_correct_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('question_save')));
    await tester.pumpAndSettle();

    expect(exams.addedQuestions, hasLength(1));
    final draft = exams.addedQuestions.single;
    expect(draft.marks, 5);
    expect(draft.options.map((option) => option.optionText).toList(), labels);
    final correct = draft.options.where((option) => option.isCorrect).toList();
    expect(correct, hasLength(1));
    expect(correct.single.optionText, 'O(log n)');
    expect(find.text('parent screen'), findsOneWidget);
  });

  testWidgets('options can be added up to the maximum', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    for (var added = 0; added < 4; added++) {
      await tester.tap(find.byKey(const Key('add_option')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('option_text_7')), findsOneWidget);
    // At eight options the control disappears rather than failing on the server.
    expect(find.byKey(const Key('add_option')), findsNothing);
  });

  testWidgets('the last two options cannot be removed', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('option_remove_3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('option_remove_2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('option_text_2')), findsNothing);
    final remove = tester.widget<IconButton>(find.byKey(const Key('option_remove_1')));
    expect(remove.onPressed, isNull, reason: 'a question needs at least two options');
  });

  testWidgets('editing loads the existing question and keeps its answer marked',
      (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();
    final existing = buildExamQuestion(
      examId: 10,
      text: 'Which is a NoSQL database?',
      options: const ['MySQL', 'MongoDB'],
      correctIndex: 1,
      marks: 4,
    );

    await tester.pumpWidget(
      wrap(
        QuestionBuilderScreen(examId: 10, courseId: 1, existing: existing),
        exams: exams,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Which is a NoSQL database?'), findsOneWidget);
    expect(find.text('MongoDB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('question_save')));
    await tester.pumpAndSettle();

    expect(exams.updatedQuestions, hasLength(1));
    final draft = exams.updatedQuestions.single;
    expect(draft.marks, 4);
    final correct = draft.options.where((option) => option.isCorrect).single;
    expect(correct.optionText, 'MongoDB', reason: 'the marked answer must survive a reload');
  });

  group('question types', () {
    Future<void> chooseType(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const Key('question_type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a short answer question hides the options entirely', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository();
      await tester.pumpWidget(
        wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: exams),
      );
      await tester.pumpAndSettle();

      await chooseType(tester, 'Short answer');

      expect(find.byKey(const Key('option_text_0')), findsNothing);
      expect(find.byKey(const Key('add_option')), findsNothing);
      expect(find.text('Marked by you'), findsOneWidget);
    });

    testWidgets('a short answer question saves without options', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository();
      await tester.pumpWidget(
        wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: exams),
      );
      await tester.pumpAndSettle();

      await chooseType(tester, 'Short answer');
      await tester.enterText(
        find.byKey(const Key('question_text')), 'Explain TCP versus UDP.');
      await tester.enterText(find.byKey(const Key('question_marks')), '10');
      await tester.tap(find.byKey(const Key('question_save')));
      await tester.pumpAndSettle();

      expect(exams.addedQuestions, hasLength(1));
      final draft = exams.addedQuestions.single;
      expect(draft.type, QuestionType.shortAnswer);
      expect(draft.options, isEmpty);
      expect(draft.marks, 10);
    });

    testWidgets('a code question offers its language and limits', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository();
      await tester.pumpWidget(
        wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: exams),
      );
      await tester.pumpAndSettle();

      await chooseType(tester, 'Code');
      expect(find.byKey(const Key('code_language')), findsOneWidget);
      expect(find.textContaining('not executed by the platform'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('question_text')), 'Implement binary search.');
      await tester.enterText(find.byKey(const Key('question_marks')), '10');
      await tester.tap(find.byKey(const Key('question_save')));
      await tester.pumpAndSettle();

      final draft = exams.addedQuestions.single;
      expect(draft.type, QuestionType.codeAnswer);
      expect(draft.language, 'cpp');
      expect(draft.timeLimitSeconds, 2);
      expect(draft.memoryLimitMb, 256);
    });

    testWidgets('an image question will not save without its image', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository();
      await tester.pumpWidget(
        wrap(const QuestionBuilderScreen(examId: 10, courseId: 1), exams: exams),
      );
      await tester.pumpAndSettle();

      await chooseType(tester, 'Image with text options');
      expect(find.byKey(const Key('question_image')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('question_text')), 'Which gate is shown?');
      for (var index = 0; index < 4; index++) {
        await tester.enterText(find.byKey(Key('option_text_$index')), 'Gate $index');
      }
      await tester.tap(find.byKey(const Key('question_save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('needs an image'), findsOneWidget);
      expect(exams.addedQuestions, isEmpty, reason: 'nothing should reach the network');
    });
  });
}
