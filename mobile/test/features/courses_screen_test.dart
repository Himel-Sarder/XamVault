import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/shared/courses_screen.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/course_deletion_impact.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

class _SignedIn extends AuthNotifier {
  _SignedIn(this.user);
  final User user;
  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated, user: user);
}

const _admin = User(id: 1, userId: 'admin', name: 'Admin', role: UserRole.admin);
const _student =
    User(id: 3, userId: '20261234', name: 'A Student', role: UserRole.student);

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

FakeCourseRepository mixedShelf() => FakeCourseRepository(
      courses: const [
        Course(
          id: 1,
          courseCode: 'CSE-301',
          courseName: 'Database Management System',
          createdBy: 2,
        ),
        Course(
          id: 2,
          courseCode: 'CSE-205',
          courseName: 'Digital Logic Design',
          createdBy: 2,
          isActive: false,
        ),
      ],
    );

Widget wrap({required User as, FakeCourseRepository? courses}) => ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _SignedIn(as)),
        courseRepositoryProvider.overrideWithValue(courses ?? mixedShelf()),
        departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
        adminRepositoryProvider.overrideWithValue(FakeAdminRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const CoursesScreen(title: 'All Courses'),
      ),
    );

void main() {
  group('the list itself', () {
    testWidgets('it shows every course, with no archive to hide behind',
        (tester) async {
      // Archiving was removed: a course is on the list or it is deleted, and deleting
      // says what it would destroy first.
      tall(tester);
      await tester.pumpWidget(wrap(as: _admin));
      await tester.pumpAndSettle();

      expect(find.text('CSE-301'), findsOneWidget);
      expect(find.text('CSE-205'), findsOneWidget);
      expect(find.byKey(const Key('course_filter_all')), findsNothing);
      expect(find.byKey(const Key('archive_course_1')), findsNothing);
      expect(find.text('Archived'), findsNothing);
    });

    testWidgets('an empty list is explained rather than blank', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(
        as: _student,
        courses: FakeCourseRepository(courses: const []),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No courses'), findsOneWidget);
    });
  });

  group('deleting a course', () {
    testWidgets('it counts what would go before asking', (tester) async {
      tall(tester);
      final courses = mixedShelf()
        ..impact = const CourseDeletionImpact(
          exams: 3,
          questionsOnThoseExams: 20,
          attempts: 47,
          results: 31,
          enrolments: 12,
        );
      await tester.pumpWidget(wrap(as: _admin, courses: courses));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_course_1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 exams'), findsOneWidget);
      expect(find.textContaining('47 attempts'), findsOneWidget);
      expect(find.textContaining('31 results'), findsOneWidget);
      expect(find.textContaining('12 enrolments'), findsOneWidget);
      expect(find.text('Delete everything'), findsOneWidget);
    });

    testWidgets('it says the questions are kept', (tester) async {
      // They live in their author's bank, not on the course, and deleting a course
      // should not quietly empty the bank of everything ever set on it.
      tall(tester);
      final courses = mixedShelf()
        ..impact = const CourseDeletionImpact(
          exams: 1,
          questionsOnThoseExams: 8,
          attempts: 0,
          results: 0,
          enrolments: 0,
        );
      await tester.pumpWidget(wrap(as: _admin, courses: courses));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_course_1')));
      await tester.pumpAndSettle();

      expect(find.textContaining("stay in their author's bank"), findsOneWidget);
    });

    testWidgets('an untouched course deletes quietly', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(as: _admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_course_1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('nothing else goes with it'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('confirming actually deletes it', (tester) async {
      tall(tester);
      final courses = mixedShelf();
      await tester.pumpWidget(wrap(as: _admin, courses: courses));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_course_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_course')));
      await tester.pumpAndSettle();

      expect(courses.deleted, [1]);
    });

    testWidgets('keeping it deletes nothing', (tester) async {
      tall(tester);
      final courses = mixedShelf();
      await tester.pumpWidget(wrap(as: _admin, courses: courses));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_course_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();

      expect(courses.deleted, isEmpty);
    });

    testWidgets('a student is offered no delete button at all', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(as: _student));
      await tester.pumpAndSettle();

      // The API refuses them anyway; the screen should not offer it either.
      expect(find.byKey(const Key('delete_course_1')), findsNothing);
    });
  });
}
