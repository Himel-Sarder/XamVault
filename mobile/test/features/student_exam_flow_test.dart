import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/student/available_exams_screen.dart';
import 'package:uniexam/features/student/my_requests_screen.dart';
import 'package:uniexam/features/student/student_exam_detail_screen.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/join_request.dart';
import 'package:uniexam/models/student_exam.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeStudentRepository student}) {
  return ProviderScope(
    overrides: [studentRepositoryProvider.overrideWithValue(student)],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('available exams', () {
    testWidgets('lists what the server made visible', (tester) async {
      final student = FakeStudentRepository(exams: [
        buildStudentExam(id: 10, title: 'Mid Term Quiz', questionCount: 4, totalMarks: 20),
      ]);
      await tester.pumpWidget(wrap(const AvailableExamsScreen(), student: student));
      await tester.pumpAndSettle();

      expect(find.text('Mid Term Quiz'), findsOneWidget);
      expect(find.text('CSE-301'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.textContaining('4 questions'), findsOneWidget);
    });

    testWidgets('explains an empty list instead of showing a blank page', (tester) async {
      await tester.pumpWidget(
        wrap(const AvailableExamsScreen(), student: FakeStudentRepository(exams: const [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('No exams right now'), findsOneWidget);
    });

    testWidgets('shows the request state on the tile once one exists', (tester) async {
      final student = FakeStudentRepository(exams: [
        buildStudentExam(joinRequestStatus: JoinRequestStatus.pending),
      ]);
      await tester.pumpWidget(wrap(const AvailableExamsScreen(), student: student));
      await tester.pumpAndSettle();

      expect(find.text('Awaiting approval'), findsOneWidget);
    });

    testWidgets('a finished exam is not listed by default', (tester) async {
      final student = FakeStudentRepository(exams: [
        buildStudentExam(id: 11, title: 'Old Exam', availability: ExamAvailability.closed),
      ]);
      await tester.pumpWidget(wrap(const AvailableExamsScreen(), student: student));
      await tester.pumpAndSettle();

      expect(find.text('Old Exam'), findsNothing);
      expect(find.text('No exams right now'), findsOneWidget);
    });
  });

  group('my requests', () {
    testWidgets('lists the student own requests with their status', (tester) async {
      final student = FakeStudentRepository(requests: [
        MyJoinRequest(
          id: 1,
          examId: 10,
          examTitle: 'Mid Term Quiz',
          courseCode: 'CSE-301',
          status: JoinRequestStatus.approved,
          requestedAt: DateTime(2026, 8, 23, 10, 30),
        ),
      ]);
      await tester.pumpWidget(wrap(const MyRequestsScreen(), student: student));
      await tester.pumpAndSettle();

      expect(find.text('Mid Term Quiz'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.textContaining('CSE-301'), findsOneWidget);
    });

    testWidgets('says what to do when there are none', (tester) async {
      await tester.pumpWidget(
        wrap(const MyRequestsScreen(), student: FakeStudentRepository(requests: const [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('No requests yet'), findsOneWidget);
    });
  });

  group('exam details', () {
    testWidgets('offers the join button when the server says it may', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository(exams: [buildStudentExam(id: 10)]);
      await tester.pumpWidget(
        wrap(const StudentExamDetailScreen(examId: 10), student: student),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not requested yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('request_to_join')));
      await tester.pumpAndSettle();

      expect(student.joinRequestsSent, [10]);
      expect(find.text('Request sent to your teacher'), findsOneWidget);
    });

    testWidgets('hides the button once a request is pending', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository(exams: [
        buildStudentExam(id: 10, joinRequestStatus: JoinRequestStatus.pending),
      ]);
      await tester.pumpWidget(
        wrap(const StudentExamDetailScreen(examId: 10), student: student),
      );
      await tester.pumpAndSettle();

      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.byKey(const Key('request_to_join')), findsNothing);
    });

    testWidgets('an approved student is told they are in', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository(exams: [
        buildStudentExam(id: 10, joinRequestStatus: JoinRequestStatus.approved),
      ]);
      await tester.pumpWidget(
        wrap(const StudentExamDetailScreen(examId: 10), student: student),
      );
      await tester.pumpAndSettle();

      expect(find.text('You are approved'), findsOneWidget);
      expect(find.byKey(const Key('request_to_join')), findsNothing);
    });

    testWidgets('a rejected student may ask again', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository(exams: [
        buildStudentExam(id: 10, joinRequestStatus: JoinRequestStatus.rejected),
      ]);
      await tester.pumpWidget(
        wrap(const StudentExamDetailScreen(examId: 10), student: student),
      );
      await tester.pumpAndSettle();

      expect(find.text('Request not approved'), findsOneWidget);
      expect(find.byKey(const Key('request_to_join')), findsOneWidget);
    });

    testWidgets('a finished exam offers nothing', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository(exams: [
        buildStudentExam(id: 10, availability: ExamAvailability.closed),
      ]);
      await tester.pumpWidget(
        wrap(const StudentExamDetailScreen(examId: 10), student: student),
      );
      await tester.pumpAndSettle();

      expect(find.text('This exam has ended.'), findsOneWidget);
      expect(find.byKey(const Key('request_to_join')), findsNothing);
    });

    testWidgets('the secure-mode warning is shown before the button', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository(exams: [buildStudentExam(id: 10)]);
      await tester.pumpWidget(
        wrap(const StudentExamDetailScreen(examId: 10), student: student),
      );
      await tester.pumpAndSettle();

      expect(find.text('Secure mode'), findsOneWidget);
      expect(find.textContaining('locked to the exam'), findsOneWidget);
    });

    testWidgets('a refused request surfaces the server message', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository(exams: [buildStudentExam(id: 10)]);
      await tester.pumpWidget(
        wrap(const StudentExamDetailScreen(examId: 10), student: student),
      );
      await tester.pumpAndSettle();

      student.failWith = const ApiException(
        'You already have a request waiting for approval',
        statusCode: 409,
      );
      await tester.tap(find.byKey(const Key('request_to_join')));
      await tester.pumpAndSettle();

      // The refusal is reported in a snackbar. The screen also re-reads the exam
      // afterwards, so be specific about which one is being asserted.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('You already have a request waiting for approval'),
        ),
        findsOneWidget,
      );
    });
  });
}
