import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/course_detail_screen.dart';
import 'package:uniexam/features/teacher/exam_form_screen.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {FakeExamRepository? exams, FakeCourseRepository? courses}) {
  return ProviderScope(
    overrides: [
      examRepositoryProvider.overrideWithValue(exams ?? FakeExamRepository()),
      courseRepositoryProvider.overrideWithValue(courses ?? FakeCourseRepository()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

/// Hosts a screen inside a real GoRouter with a parent route beneath it.
///
/// The form calls `context.pop()` after saving, so a bare MaterialApp is not enough -
/// and a nested route gives it something to pop back to, exactly as in the app.
Widget wrapRouted(Widget child, {FakeExamRepository? exams, FakeCourseRepository? courses}) {
  final router = GoRouter(
    initialLocation: '/form',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('parent screen'))),
        routes: [GoRoute(path: 'form', builder: (_, _) => child)],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      examRepositoryProvider.overrideWithValue(exams ?? FakeExamRepository()),
      courseRepositoryProvider.overrideWithValue(courses ?? FakeCourseRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// The exam form is taller than the default 800px test surface, so the save button is
/// never built and cannot be tapped. A tall viewport keeps these tests about the form's
/// behaviour rather than about scrolling.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('course detail', () {
    testWidgets('lists the exams in the course', (tester) async {
      final exams = FakeExamRepository(exams: [
        buildExam(id: 10, title: 'Mid Term Quiz', questionCount: 3, totalMarks: 12),
      ]);
      await tester.pumpWidget(wrap(const CourseDetailScreen(courseId: 1), exams: exams));
      await tester.pumpAndSettle();

      expect(find.text('Mid Term Quiz'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.textContaining('3 questions'), findsOneWidget);
      expect(find.textContaining('12 marks'), findsOneWidget);
    });

    testWidgets('explains what to do when there are no exams', (tester) async {
      await tester.pumpWidget(
        wrap(const CourseDetailScreen(courseId: 1), exams: FakeExamRepository(exams: [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('No exams yet'), findsOneWidget);
      expect(find.byKey(const Key('create_exam_fab')), findsOneWidget);
    });
  });

  group('exam form', () {
    testWidgets('will not submit without a title', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository();
      await tester.pumpWidget(wrap(const ExamFormScreen(courseId: 1), exams: exams));

      await tester.tap(find.byKey(const Key('exam_save')));
      await tester.pumpAndSettle();

      expect(find.text('Give the exam a title'), findsOneWidget);
      expect(exams.createdExams, isEmpty, reason: 'nothing should reach the network');
    });

    testWidgets('rejects a duration outside the allowed range', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository();
      await tester.pumpWidget(wrap(const ExamFormScreen(courseId: 1), exams: exams));

      await tester.enterText(find.byKey(const Key('exam_title')), 'Quiz');
      await tester.enterText(find.byKey(const Key('exam_duration')), '0');
      await tester.tap(find.byKey(const Key('exam_save')));
      await tester.pumpAndSettle();

      expect(find.text('Duration must be at least 1 minute'), findsOneWidget);
      expect(exams.createdExams, isEmpty);
    });

    testWidgets('creates the exam with the chosen settings', (tester) async {
      useTallSurface(tester);
      final exams = FakeExamRepository();
      await tester.pumpWidget(wrapRouted(const ExamFormScreen(courseId: 7), exams: exams));

      await tester.enterText(find.byKey(const Key('exam_title')), 'Mid Term Quiz');
      await tester.enterText(find.byKey(const Key('exam_duration')), '45');
      await tester.tap(find.byKey(const Key('setting_shuffle_questions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exam_save')));
      await tester.pumpAndSettle();

      expect(exams.createdExams, hasLength(1));
      final sent = exams.createdExams.single;
      expect(sent['course_id'], 7);
      expect(sent['title'], 'Mid Term Quiz');
      expect(sent['duration_minutes'], 45);
      expect((sent['settings'] as ExamSettings).shuffleQuestions, isTrue);
      // ...and the form closes, returning the teacher to where they came from.
      expect(find.text('parent screen'), findsOneWidget);
    });
  });
}
