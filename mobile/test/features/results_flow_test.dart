import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/features/student/my_results_screen.dart';
import 'package:uniexam/features/teacher/exam_results_screen.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrapStudent(Widget child, FakeStudentRepository student) {
  return ProviderScope(
    overrides: [studentRepositoryProvider.overrideWithValue(student)],
    child: MaterialApp(home: child),
  );
}

Widget wrapTeacher(Widget child, FakeExamRepository exams) {
  return ProviderScope(
    overrides: [examRepositoryProvider.overrideWithValue(exams)],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('student results', () {
    testWidgets('shows the score, the total and the percentage', (tester) async {
      final student = FakeStudentRepository()
        ..results = [buildExamResult(totalScore: 12, totalMarks: 15, percentage: 80)];

      await tester.pumpWidget(wrapStudent(const MyResultsScreen(), student));
      await tester.pumpAndSettle();

      expect(find.text('Mid Term Quiz'), findsOneWidget);
      expect(find.text('CSE-301'), findsOneWidget);
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('12 out of 15 marks'), findsOneWidget);
    });

    testWidgets('explains an empty list', (tester) async {
      await tester.pumpWidget(wrapStudent(const MyResultsScreen(), FakeStudentRepository()));
      await tester.pumpAndSettle();

      expect(find.text('No results yet'), findsOneWidget);
      expect(find.textContaining('releases the marks'), findsOneWidget);
    });
  });

  group('teacher results', () {
    testWidgets('summarises the cohort and lists each student', (tester) async {
      final exams = FakeExamRepository()
        ..results = [
          buildTeacherResult(id: 1, studentName: 'Alice', totalScore: 15, percentage: 100),
          buildTeacherResult(
              id: 2, studentName: 'Bob', studentNumber: '20265678',
              totalScore: 6, percentage: 40),
        ];

      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('70.0%'), findsOneWidget, reason: 'average of 100 and 40');
      expect(find.text('100.0%'), findsOneWidget, reason: 'highest');
      expect(find.text('40.0%'), findsOneWidget, reason: 'lowest');
    });

    testWidgets('releasing marks asks first, then publishes', (tester) async {
      final exams = FakeExamRepository()..results = [buildTeacherResult()];

      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      expect(find.textContaining('Release 1 result'), findsOneWidget);
      await tester.tap(find.byKey(const Key('publish_results')));
      await tester.pumpAndSettle();

      expect(find.text('Release these marks?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Release'));
      await tester.pumpAndSettle();

      expect(exams.publishResultsCalls, 1);
      // Once released there is nothing left to release.
      expect(find.byKey(const Key('publish_results')), findsNothing);
    });

    testWidgets('cancelling leaves the marks unreleased', (tester) async {
      final exams = FakeExamRepository()..results = [buildTeacherResult()];

      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('publish_results')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(exams.publishResultsCalls, 0);
      expect(find.byKey(const Key('publish_results')), findsOneWidget);
    });

    testWidgets('already-released marks offer no release button', (tester) async {
      final exams = FakeExamRepository()
        ..results = [buildTeacherResult(status: 'published')];

      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('publish_results')), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('says so before anyone has submitted', (tester) async {
      await tester.pumpWidget(
        wrapTeacher(const ExamResultsScreen(examId: 10), FakeExamRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No submissions yet'), findsOneWidget);
    });
  });
}
