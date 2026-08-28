import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/course_form_screen.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

class _SignedIn extends AuthNotifier {
  _SignedIn(this.user);
  final User user;
  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated, user: user);
}

const _admin = User(id: 1, userId: 'admin', name: 'Admin', role: UserRole.admin);
const _teacher =
    User(id: 2, userId: 'T1001', name: 'Dr Demo Teacher', role: UserRole.teacher);

FakeCourseRepository courseHeldBy(String? teacherName) => FakeCourseRepository(
      courses: [
        Course(
          id: 1,
          courseCode: 'CSE-301',
          courseName: 'Database Management System',
          createdBy: 2,
          teacherName: teacherName,
        ),
      ],
    );

Widget wrap({
  required User as,
  FakeCourseRepository? courses,
  FakeAdminRepository? admin,
}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _SignedIn(as)),
        courseRepositoryProvider.overrideWithValue(courses ?? courseHeldBy('Dr Demo Teacher')),
        departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
        adminRepositoryProvider.overrideWithValue(
          admin ?? FakeAdminRepository(users: [_teacher]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const CourseFormScreen(courseId: 1),
      ),
    );

void main() {
  group('who runs a course', () {
    testWidgets('an admin sees who holds it', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(as: _admin));
      await tester.pumpAndSettle();

      expect(find.text('Teacher in charge'), findsOneWidget);
      expect(find.text('Dr Demo Teacher'), findsOneWidget);
    });

    testWidgets('an unassigned course says so rather than showing a blank',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(as: _admin, courses: courseHeldBy(null)));
      await tester.pumpAndSettle();

      expect(find.text('Nobody assigned yet'), findsOneWidget);
    });

    testWidgets('a teacher is not offered the control at all', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(as: _teacher));
      await tester.pumpAndSettle();

      // Handing work to someone else is an administrative act, not an editorial one.
      expect(find.byKey(const Key('assign_teacher')), findsNothing);
    });
  });

  group('assigning', () {
    testWidgets('picking a teacher sends the assignment', (tester) async {
      tall(tester);
      final courses = courseHeldBy('Dr Demo Teacher');
      await tester.pumpWidget(wrap(as: _admin, courses: courses));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assign_teacher')));
      await tester.pumpAndSettle();
      expect(find.text('Who runs this course?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('assign_T1001')));
      await tester.pumpAndSettle();

      expect(courses.assigned.single.courseId, 1);
      expect(courses.assigned.single.teacher, 'T1001');
    });

    testWidgets('it says what stayed with the previous teacher', (tester) async {
      tall(tester);
      final courses = courseHeldBy('Dr Demo Teacher')..examsKeptOnAssign = 2;
      await tester.pumpWidget(wrap(as: _admin, courses: courses));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assign_teacher')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign_T1001')));
      await tester.pumpAndSettle();

      // An exam is somebody's work; the new holder should not find that out by
      // failing to open a paper they expected to inherit.
      expect(find.textContaining('2 exams stayed'), findsOneWidget);
    });

    testWidgets('a clean handover does not mention exams', (tester) async {
      tall(tester);
      final courses = courseHeldBy('Dr Demo Teacher')..examsKeptOnAssign = 0;
      await tester.pumpWidget(wrap(as: _admin, courses: courses));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assign_teacher')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign_T1001')));
      await tester.pumpAndSettle();

      expect(find.textContaining('stayed with'), findsNothing);
      expect(find.textContaining('now runs this course'), findsOneWidget);
    });

    testWidgets('no teacher accounts is stated, not an empty list', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        wrap(as: _admin, admin: FakeAdminRepository(users: const [])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assign_teacher')));
      await tester.pumpAndSettle();

      expect(find.text('No teacher accounts exist yet.'), findsOneWidget);
    });
  });
}
