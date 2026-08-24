import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/features/teacher/question_bank_screen.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeQuestionBankRepository bank}) {
  return ProviderScope(
    overrides: [
      questionBankRepositoryProvider.overrideWithValue(bank),
      examRepositoryProvider.overrideWithValue(FakeExamRepository()),
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
  group('browsing the library', () {
    testWidgets('shows a question with its topic and usage', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [
        buildBankQuestion(questionText: 'What is normalization?', usedInExams: 2),
      ]);

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      expect(find.text('What is normalization?'), findsOneWidget);
      expect(find.text('Databases'), findsWidgets);
      expect(find.text('Used in 2 exams'), findsOneWidget);
    });

    testWidgets('says when a question is in a published exam', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [
        buildBankQuestion(usedInExams: 1, usedInPublished: true),
      ]);

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      expect(find.text('Used in 1 exam (one published)'), findsOneWidget);
    });

    testWidgets('an empty library explains what it is for', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: []);

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.textContaining('reused across exams'), findsOneWidget);
    });

    testWidgets('searching asks the server rather than filtering locally',
        (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository();

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bank_search')), 'deadlock');
      await tester.pumpAndSettle();

      expect(bank.lastFilter?.search, 'deadlock');
    });

    testWidgets('choosing a type filter is sent to the server', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository();

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Any type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Short answer').last);
      await tester.pumpAndSettle();

      expect(bank.lastFilter?.type, QuestionType.shortAnswer);
    });
  });

  group('curating the library', () {
    testWidgets('an unused question can be deleted, after confirmation', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [
        buildBankQuestion(id: 300, usedInExams: 0),
      ]);

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_bank_question_300')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this question?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(bank.deleted, [300]);
    });

    testWidgets('a question in use cannot be deleted', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [
        buildBankQuestion(id: 300, usedInExams: 1),
      ]);

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      // Refused server-side too; the disabled button only avoids a pointless tap.
      expect(find.text('In use'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const Key('delete_bank_question_300')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [buildBankQuestion(id: 300)]);

      await tester.pumpWidget(wrap(const QuestionBankScreen(), bank: bank));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_bank_question_300')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(bank.deleted, isEmpty);
    });
  });

  group('picking questions for an exam', () {
    testWidgets('nothing is added until questions are selected', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [buildBankQuestion(id: 300)]);

      await tester.pumpWidget(
        wrap(const QuestionBankScreen(selectionFor: 10), bank: bank),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose questions'), findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(
        find.byKey(const Key('attach_selected')),
      );
      expect(fab.onPressed, isNull);
    });

    testWidgets('selected questions are attached to the exam, in order', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [
        buildBankQuestion(id: 300, questionText: 'First'),
        buildBankQuestion(id: 301, questionText: 'Second'),
      ]);

      await tester.pumpWidget(
        wrap(const QuestionBankScreen(selectionFor: 10), bank: bank),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bank_question_300')));
      await tester.tap(find.byKey(const Key('bank_question_301')));
      await tester.pumpAndSettle();
      expect(find.text('Add 2 to exam'), findsOneWidget);

      await tester.tap(find.byKey(const Key('attach_selected')));
      await tester.pumpAndSettle();

      expect(bank.attached, hasLength(1));
      expect(bank.attached.single.examId, 10);
      expect(bank.attached.single.questionIds, [300, 301]);
    });

    testWidgets('tapping a selected question deselects it', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [buildBankQuestion(id: 300)]);

      await tester.pumpWidget(
        wrap(const QuestionBankScreen(selectionFor: 10), bank: bank),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bank_question_300')));
      await tester.pumpAndSettle();
      expect(find.text('Add 1 to exam'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bank_question_300')));
      await tester.pumpAndSettle();
      expect(find.text('Select questions'), findsOneWidget);
    });

    testWidgets('the delete action is absent while picking', (tester) async {
      useTallSurface(tester);
      final bank = FakeQuestionBankRepository(questions: [buildBankQuestion(id: 300)]);

      await tester.pumpWidget(
        wrap(const QuestionBankScreen(selectionFor: 10), bank: bank),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_bank_question_300')), findsNothing);
    });
  });
}
