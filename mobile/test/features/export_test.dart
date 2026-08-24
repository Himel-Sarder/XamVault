import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/student/my_results_screen.dart';
import 'package:uniexam/features/teacher/exam_results_screen.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrapTeacher(Widget child, FakeExamRepository exams) {
  return ProviderScope(
    overrides: [examRepositoryProvider.overrideWithValue(exams)],
    child: MaterialApp(home: child),
  );
}

Widget wrapStudent(Widget child, FakeStudentRepository student) {
  return ProviderScope(
    overrides: [studentRepositoryProvider.overrideWithValue(student)],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('teacher exports', () {
    testWidgets('both formats are offered', (tester) async {
      final exams = FakeExamRepository()..results = [buildTeacherResult()];
      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_pdf')), findsOneWidget);
      expect(find.byKey(const Key('export_excel')), findsOneWidget);
    });

    testWidgets('exporting a PDF fetches it through the authenticated client',
        (tester) async {
      final exams = FakeExamRepository()..results = [buildTeacherResult()];
      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export_pdf')));
      await tester.pumpAndSettle();

      expect(exams.exported, ['pdf']);
      // The test platform cannot save a file, and the app says so rather than failing
      // silently — the fetch still happened.
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('exporting a spreadsheet uses the spreadsheet endpoint', (tester) async {
      final exams = FakeExamRepository()..results = [buildTeacherResult()];
      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export_excel')));
      await tester.pumpAndSettle();

      expect(exams.exported, ['excel']);
    });

    testWidgets('a refused export surfaces the server message', (tester) async {
      final exams = FakeExamRepository()
        ..results = [buildTeacherResult()]
        ..failExports = const ApiException('Exam not found', statusCode: 404);

      await tester.pumpWidget(wrapTeacher(const ExamResultsScreen(examId: 10), exams));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export_pdf')));
      await tester.pumpAndSettle();

      expect(find.text('Exam not found'), findsOneWidget);
    });
  });

  group('student export', () {
    testWidgets('a released result offers a PDF', (tester) async {
      final student = FakeStudentRepository()..results = [buildExamResult(id: 700)];
      await tester.pumpWidget(wrapStudent(const MyResultsScreen(), student));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download_result_700')), findsOneWidget);

      await tester.tap(find.byKey(const Key('download_result_700')));
      await tester.pumpAndSettle();

      expect(student.exportedResults, [700]);
    });
  });
}
