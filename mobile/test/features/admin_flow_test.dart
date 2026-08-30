import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/shared/change_password_screen.dart';
import 'package:uniexam/features/teacher/course_form_screen.dart';
import 'package:uniexam/features/teacher/departments_screen.dart';
import 'package:uniexam/features/teacher/enrollments_screen.dart';
import 'package:uniexam/features/teacher/users_screen.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/models/enrollment.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/repositories/department_repository.dart';

import 'fakes.dart';

Widget wrap(
  Widget child, {
  FakeCourseRepository? course,
  DepartmentRepository? department,
  FakeAdminRepository? admin,
  FakeAuthRepository? auth,
}) {
  return ProviderScope(
    overrides: [
      courseRepositoryProvider.overrideWithValue(course ?? FakeCourseRepository()),
      departmentRepositoryProvider
          .overrideWithValue(department ?? FakeDepartmentRepository()),
      adminRepositoryProvider.overrideWithValue(admin ?? FakeAdminRepository()),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Enrollment seat(int n, String userId) => Enrollment(
      id: n,
      courseId: 1,
      studentId: 50 + n,
      student: UserSummary(
        id: 50 + n,
        userId: userId,
        name: 'Student $userId',
        role: UserRole.student,
      ),
    );

void main() {
  group('changing your own password', () {
    testWidgets('the consequence is stated before the change, not after', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(const ChangePasswordScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('signed out'), findsWidgets);
    });

    testWidgets('a mistyped confirmation is caught without a round trip', (tester) async {
      useTallSurface(tester);
      final auth = FakeAuthRepository();
      await tester.pumpWidget(wrap(const ChangePasswordScreen(), auth: auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('current_password')), 'oldpassword');
      await tester.enterText(find.byKey(const Key('new_password')), 'newpassword1');
      await tester.enterText(find.byKey(const Key('confirm_password')), 'newpassword2');
      await tester.tap(find.byKey(const Key('save_password')));
      await tester.pumpAndSettle();

      expect(find.text('The two passwords do not match'), findsOneWidget);
      expect(auth.passwordChanges, isEmpty, reason: 'nothing should have been sent');
    });

    testWidgets('reusing the current password is refused', (tester) async {
      useTallSurface(tester);
      final auth = FakeAuthRepository();
      await tester.pumpWidget(wrap(const ChangePasswordScreen(), auth: auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('current_password')), 'samepassword');
      await tester.enterText(find.byKey(const Key('new_password')), 'samepassword');
      await tester.enterText(find.byKey(const Key('confirm_password')), 'samepassword');
      await tester.tap(find.byKey(const Key('save_password')));
      await tester.pumpAndSettle();

      expect(find.textContaining('must differ'), findsOneWidget);
      expect(auth.passwordChanges, isEmpty);
    });

    testWidgets('a good change is sent once', (tester) async {
      useTallSurface(tester);
      final auth = FakeAuthRepository();
      await tester.pumpWidget(wrap(const ChangePasswordScreen(), auth: auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('current_password')), 'oldpassword');
      await tester.enterText(find.byKey(const Key('new_password')), 'newpassword1');
      await tester.enterText(find.byKey(const Key('confirm_password')), 'newpassword1');
      await tester.tap(find.byKey(const Key('save_password')));
      await tester.pumpAndSettle();

      expect(auth.passwordChanges, [('oldpassword', 'newpassword1')]);
    });
  });

  group('creating a course', () {
    testWidgets('the code is editable when creating', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(const CourseFormScreen()));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('course_code')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.readOnly, isFalse);
    });

    testWidgets('the form sends what was typed', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository();
      await tester.pumpWidget(wrap(const CourseFormScreen(), course: course));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('course_code')), 'CSE-401');
      await tester.enterText(find.byKey(const Key('course_name')), 'Compilers');
      await tester.tap(find.byKey(const Key('course_save')));
      await tester.pumpAndSettle();

      expect(course.created.single.courseCode, 'CSE-401');
      expect(course.created.single.courseName, 'Compilers');
    });

    testWidgets('a course without a name is refused before sending', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository();
      await tester.pumpWidget(wrap(const CourseFormScreen(), course: course));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('course_code')), 'CSE-401');
      await tester.tap(find.byKey(const Key('course_save')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a course name'), findsOneWidget);
      expect(course.created, isEmpty);
    });

    testWidgets('the code cannot be changed once the course exists', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(const CourseFormScreen(courseId: 1)));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('course_code')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.readOnly, isTrue);
      expect(find.textContaining('cannot be changed'), findsOneWidget);
    });

    testWidgets('a department list that fails to load does not block the form',
        (tester) async {
      useTallSurface(tester);
      final departments = FailingDepartmentRepository();
      final course = FakeCourseRepository();
      await tester.pumpWidget(
        wrap(const CourseFormScreen(), course: course, department: departments),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be loaded'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('course_code')), 'CSE-401');
      await tester.enterText(find.byKey(const Key('course_name')), 'Compilers');
      await tester.tap(find.byKey(const Key('course_save')));
      await tester.pumpAndSettle();

      // The field is optional, so the course still saves.
      expect(course.created, hasLength(1));
    });
  });

  group('the roll', () {
    testWidgets('an empty roll explains both ways to fill it', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(const EnrollmentsScreen(courseId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('Nobody is enrolled yet'), findsOneWidget);
      expect(find.byKey(const Key('bulk_enrol')), findsOneWidget);
      expect(find.byKey(const Key('enrol_one')), findsOneWidget);
    });

    testWidgets('enrolled students are listed by name and ID', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository()..roll = [seat(1, '20261234')];
      await tester.pumpWidget(wrap(const EnrollmentsScreen(courseId: 1), course: course));
      await tester.pumpAndSettle();

      expect(find.text('Student 20261234'), findsOneWidget);
      expect(find.text('20261234'), findsOneWidget);
      expect(find.text('1 enrolled'), findsOneWidget);
    });

    testWidgets('removing a student asks first', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository()..roll = [seat(1, '20261234')];
      await tester.pumpWidget(wrap(const EnrollmentsScreen(courseId: 1), course: course));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remove_51')));
      await tester.pumpAndSettle();
      expect(find.text('Remove from course?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(course.removed, isEmpty);
    });

    testWidgets('results are kept when a student is removed, and it says so',
        (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository()..roll = [seat(1, '20261234')];
      await tester.pumpWidget(wrap(const EnrollmentsScreen(courseId: 1), course: course));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remove_51')));
      await tester.pumpAndSettle();
      expect(find.textContaining('already have are kept'), findsOneWidget);
    });
  });

  group('bulk enrolment', () {
    Future<void> openBulk(WidgetTester tester, FakeCourseRepository course) async {
      await tester.pumpWidget(wrap(const EnrollmentsScreen(courseId: 1), course: course));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk_enrol')));
      await tester.pumpAndSettle();
    }

    testWidgets('IDs separated any which way are all picked up', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository();
      await openBulk(tester, course);

      await tester.enterText(
        find.byKey(const Key('bulk_ids')),
        '20261234\n20261235, 20261236  20261237',
      );
      await tester.pumpAndSettle();
      expect(find.text('4 IDs ready'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bulk_submit')));
      await tester.pumpAndSettle();

      expect(course.bulkBatches.single,
          ['20261234', '20261235', '20261236', '20261237']);
    });

    testWidgets('a repeated ID is counted once', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository();
      await openBulk(tester, course);

      await tester.enterText(
        find.byKey(const Key('bulk_ids')),
        '20261234\n20261234\n20261235',
      );
      await tester.pumpAndSettle();
      expect(find.text('2 IDs ready'), findsOneWidget);
    });

    testWidgets('an empty list cannot be submitted', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository();
      await openBulk(tester, course);

      final button = tester.widget<FilledButton>(find.byKey(const Key('bulk_submit')));
      expect(button.onPressed, isNull);
    });

    testWidgets('the outcome names every ID that failed, and why', (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository()
        ..nextSkipped = const [
          SkippedEnrolment(studentUserId: 'ghost', reason: SkipReason.notFound),
          SkippedEnrolment(
            studentUserId: '20261235',
            reason: SkipReason.alreadyEnrolled,
          ),
        ];
      await openBulk(tester, course);

      await tester.enterText(
        find.byKey(const Key('bulk_ids')),
        'ghost 20261234 20261235',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk_submit')));
      await tester.pumpAndSettle();

      // A count alone would send the teacher back to compare two lists by eye.
      expect(find.byKey(const Key('bulk_outcome')), findsOneWidget);
      expect(find.text('Enrolled 1'), findsOneWidget);
      expect(find.text('ghost'), findsOneWidget);
      expect(find.text('No student with that ID'), findsOneWidget);
      expect(find.text('Already enrolled'), findsOneWidget);
    });

    testWidgets('a reason this build does not know is reported, not hidden',
        (tester) async {
      useTallSurface(tester);
      final course = FakeCourseRepository()
        ..nextSkipped = const [
          SkippedEnrolment(studentUserId: 'x1', reason: SkipReason.unknown),
        ];
      await openBulk(tester, course);

      await tester.enterText(find.byKey(const Key('bulk_ids')), 'x1 20261234');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Could not be enrolled'), findsOneWidget);
    });
  });

  group('departments', () {
    testWidgets('the list shows code and name', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(const DepartmentsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Computer Science'), findsOneWidget);
      expect(find.text('CSE'), findsOneWidget);
    });

    testWidgets('a new department is created with what was typed', (tester) async {
      useTallSurface(tester);
      final departments = FakeDepartmentRepository();
      await tester.pumpWidget(wrap(const DepartmentsScreen(), department: departments));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new_department')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('department_code')), 'MTH');
      await tester.enterText(find.byKey(const Key('department_name')), 'Mathematics');
      await tester.tap(find.byKey(const Key('department_submit')));
      await tester.pumpAndSettle();

      expect(departments.created.single, (code: 'MTH', name: 'Mathematics'));
    });

    testWidgets('an existing code is not editable', (tester) async {
      useTallSurface(tester);
      final departments = FakeDepartmentRepository();
      await tester.pumpWidget(wrap(const DepartmentsScreen(), department: departments));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('department_rename_1')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byKey(const Key('department_code')));
      expect(field.readOnly, isTrue);
    });

    testWidgets('a department can be renamed or deleted', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(const DepartmentsScreen()));
      await tester.pumpAndSettle();

      // Archiving is gone; deleting replaced it. Nothing is stranded by a delete --
      // every reference to a department is SET NULL server-side.
      expect(find.byKey(const Key('department_rename_1')), findsOneWidget);
      expect(find.byKey(const Key('department_delete_1')), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('an empty department deletes quietly', (tester) async {
      useTallSurface(tester);
      final departments = FakeDepartmentRepository();
      await tester.pumpWidget(wrap(const DepartmentsScreen(), department: departments));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('department_delete_1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing belongs to it'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_delete_department')));
      await tester.pumpAndSettle();

      expect(departments.deleted, [1]);
    });

    testWidgets('one with courses says they survive without a department',
        (tester) async {
      // "3 courses" must not read as "3 courses will be deleted".
      useTallSurface(tester);
      final departments = FakeDepartmentRepository()
        ..impact = const DepartmentDeletionImpact(
          courses: 3,
          teachers: 2,
          students: 40,
        );
      await tester.pumpWidget(wrap(const DepartmentsScreen(), department: departments));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('department_delete_1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 courses'), findsOneWidget);
      expect(find.textContaining('40 students'), findsOneWidget);
      expect(find.textContaining('keep everything they have'), findsOneWidget);
    });

    testWidgets('keeping it deletes nothing', (tester) async {
      useTallSurface(tester);
      final departments = FakeDepartmentRepository();
      await tester.pumpWidget(wrap(const DepartmentsScreen(), department: departments));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('department_delete_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();

      expect(departments.deleted, isEmpty);
    });
  });

  group('users', () {
    List<User> directory() => [
          const User(id: 1, userId: 'T1001', name: 'Ada Teacher', role: UserRole.teacher),
          const User(
            id: 2,
            userId: '20261234',
            name: 'Bob Student',
            role: UserRole.student,
          ),
          const User(
            id: 3,
            userId: 'gone',
            name: 'Old Account',
            role: UserRole.student,
            isActive: false,
          ),
        ];

    testWidgets('every account is listed with its role', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      expect(find.text('Ada Teacher'), findsOneWidget);
      expect(find.text('T1001 · Teacher'), findsOneWidget);
    });

    testWidgets('a deactivated account says so', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      expect(find.textContaining('deactivated'), findsOneWidget);
    });

    testWidgets('the role filter narrows the list', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('role_teacher')));
      await tester.pumpAndSettle();

      expect(admin.lastFilter?.role, UserRole.teacher);
      expect(find.text('Ada Teacher'), findsOneWidget);
      expect(find.text('Bob Student'), findsNothing);
    });

    testWidgets('deactivating comes first, and is one tap', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('user_active_1')));
      await tester.pumpAndSettle();
      expect(admin.updated.single.isActive, isFalse);
    });

    Future<void> openNewUser(WidgetTester tester, FakeAdminRepository admin) async {
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new_user')));
      await tester.pumpAndSettle();
    }

    testWidgets('a student ID that is not 8 digits is refused before sending',
        (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await openNewUser(tester, admin);

      for (final bad in ['abc', '2026', '202699999']) {
        await tester.enterText(find.byKey(const Key('new_user_id')), bad);
        await tester.enterText(find.byKey(const Key('new_user_name')), 'New Student');
        await tester.enterText(
          find.byKey(const Key('new_user_password')),
          'password123',
        );
        await tester.tap(find.byKey(const Key('new_user_submit')));
        await tester.pumpAndSettle();

        expect(find.text('A student ID is exactly 8 digits'), findsOneWidget,
            reason: '$bad should be refused');
      }
      // A mistyped roll number would otherwise become an account nobody can sign in to.
      expect(admin.created, isEmpty);
    });

    testWidgets('a student is not asked for the same number twice', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await openNewUser(tester, admin);

      // The login *is* the student number, so there is one field, not two.
      expect(find.byKey(const Key('new_user_profile_id')), findsNothing);
      expect(find.text('Student ID'), findsOneWidget);
    });

    testWidgets('an admin account is not asked for a profile ID', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await openNewUser(tester, admin);

      // 'Administrator' is also a role filter chip behind the dialog.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Administrator'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new_user_profile_id')), findsNothing);
    });

    testWidgets('a teacher may still carry a separate staff ID', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await openNewUser(tester, admin);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Teacher'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new_user_profile_id')), findsOneWidget);
    });

    testWidgets('a student is asked for a year and a half of it', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new_user')));
      await tester.pumpAndSettle();

      // Four years and two halves, not one running count of twelve.
      expect(find.byKey(const Key('new_user_year')), findsOneWidget);
      expect(find.byKey(const Key('new_user_semester')), findsOneWidget);

      await tester.tap(find.byKey(const Key('new_user_year')));
      await tester.pumpAndSettle();
      expect(find.text('4th Year'), findsWidgets);
      expect(find.text('5th Year'), findsNothing);
    });

    testWidgets('a teacher is not asked for either', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new_user')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Teacher')),
      );
      await tester.pumpAndSettle();

      // Staff are not in a year of the programme.
      expect(find.byKey(const Key('new_user_year')), findsNothing);
      expect(find.byKey(const Key('new_user_semester')), findsNothing);
    });

    testWidgets('the department picker actually lists the departments',
        (tester) async {
      useTallSurface(tester);
      final departments = FakeDepartmentRepository();
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(
        wrap(const UsersScreen(), admin: admin, department: departments),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new_user')));
      await tester.pumpAndSettle();

      // The dialog used to be handed a list read from a provider nobody had
      // subscribed to, so it was empty every single time and no department could be
      // chosen. Watching is what starts the fetch.
      await tester.tap(find.byKey(const Key('new_user_department')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Computer Science'), findsWidgets);
      expect(find.textContaining('Electrical'), findsWidgets);
    });

    testWidgets('a live account offers no delete', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      // Deactivating is the reversible version of the same intent, so it comes first.
      expect(find.byKey(const Key('delete_user_1')), findsNothing);
      // Account 3 in the directory is deactivated.
      expect(find.byKey(const Key('delete_user_3')), findsOneWidget);
    });

    testWidgets('deleting names what goes with the account', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory())
        ..impact = const {
          'courses': 0,
          'exams': 0,
          'questions': 0,
          'attempts': 4,
          'results': 2,
          'enrolments': 1,
        };
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_user_3')));
      await tester.pumpAndSettle();

      expect(find.textContaining('4 attempts'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.text('Delete everything'), findsOneWidget);
    });

    testWidgets('an account with no history deletes quietly', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_user_3')));
      await tester.pumpAndSettle();

      expect(find.textContaining('nothing else goes with them'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_delete_user')));
      await tester.pumpAndSettle();
      expect(admin.deletedUsers, [3]);
    });

    testWidgets('deleting a teacher says their work goes with them', (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory())
        ..impact = const {
          'courses': 2,
          'exams': 5,
          'questions': 12,
          'attempts': 0,
          'results': 0,
          'enrolments': 0,
          'student_attempts': 0,
          'student_results': 0,
        };
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_user_3')));
      await tester.pumpAndSettle();

      // Authoring content used to be a refusal. It is what an administrator asking to
      // delete a teacher is asking for, so it is a warning with numbers in it now.
      expect(find.textContaining('2 courses'), findsOneWidget);
      expect(find.textContaining('5 exams'), findsOneWidget);
      expect(find.textContaining('12 questions'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_delete_user')));
      await tester.pumpAndSettle();
      expect(admin.deletedUsers, [3]);
    });

    testWidgets("it names other students' work separately", (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory())
        ..impact = const {
          'courses': 1,
          'exams': 3,
          'questions': 0,
          'attempts': 0,
          'results': 0,
          'enrolments': 0,
          'student_attempts': 47,
          'student_results': 31,
        };
      await tester.pumpWidget(wrap(const UsersScreen(), admin: admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_user_3')));
      await tester.pumpAndSettle();

      // The part an administrator is least likely to have thought about: this work
      // belongs to students who are not being deleted.
      expect(find.textContaining('47 student attempts'), findsOneWidget);
      expect(find.textContaining('31 student results'), findsOneWidget);
      expect(find.textContaining('not being deleted'), findsOneWidget);
    });

    testWidgets('an 8-digit student is created with the password the admin set',
        (tester) async {
      useTallSurface(tester);
      final admin = FakeAdminRepository(users: directory());
      await openNewUser(tester, admin);

      await tester.enterText(find.byKey(const Key('new_user_id')), '20269999');
      await tester.enterText(find.byKey(const Key('new_user_name')), 'New Student');
      await tester.enterText(
        find.byKey(const Key('new_user_password')),
        'password123',
      );
      await tester.tap(find.byKey(const Key('new_user_submit')));
      await tester.pumpAndSettle();

      expect(admin.created.single, (userId: '20269999', role: UserRole.student));
    });
  });
}
