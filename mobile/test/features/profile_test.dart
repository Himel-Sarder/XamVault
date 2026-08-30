import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/shared/profile_screen.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

User student() => const User(
      id: 80,
      userId: '20261234',
      name: 'Ayesha Rahman',
      role: UserRole.student,
      email: 'ayesha@example.edu',
      department: Department(id: 1, code: 'CSE', name: 'Computer Science & Engineering'),
      studentProfile: StudentProfile(
        studentId: '20261234',
        studyYear: 3,
        semester: 2,
        session: '2025-2026',
      ),
    );

User teacher() => const User(
      id: 79,
      userId: 'T1001',
      name: 'Dr Demo Teacher',
      role: UserRole.teacher,
      department: Department(id: 1, code: 'CSE', name: 'Computer Science & Engineering'),
      teacherProfile: TeacherProfile(teacherId: 'T1001', designation: 'Lecturer'),
    );

User admin() => const User(
      id: 1,
      userId: 'admin',
      name: 'System Administrator',
      role: UserRole.admin,
    );

/// Holds one signed-in user, so the screen can be pumped without a login round trip.
class _SignedIn extends AuthNotifier {
  _SignedIn(this.user);

  final User user;

  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated, user: user);
}

Widget wrap(User user) => ProviderScope(
      overrides: [authProvider.overrideWith(() => _SignedIn(user))],
      child: MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
    );

void main() {
  group('who you are', () {
    testWidgets('the header carries the name, role and ID', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      expect(find.text('Ayesha Rahman'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('20261234'), findsWidgets);
      // Initials, so the header is not an empty circle.
      expect(find.text('AR'), findsOneWidget);
    });

    testWidgets('a long department name is shown in full', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      // It used to sit beside a fixed 110px label and get cut. Truncating a department
      // name to make a grid line up is the wrong trade.
      expect(find.text('Computer Science & Engineering'), findsOneWidget);
      expect(find.text('CSE'), findsOneWidget);
    });
  });

  group('the academic record', () {
    testWidgets('a student sees their own fields', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      expect(find.text('Student ID'), findsOneWidget);
      // Written the way the university says it, in one place, so no two screens
      // disagree about the same student.
      expect(find.text('3rd Year, 2nd Semester'), findsOneWidget);
      expect(find.text('2025-2026'), findsOneWidget);
      expect(find.text('Teacher ID'), findsNothing);
    });

    testWidgets('a teacher sees theirs instead', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(teacher()));
      await tester.pumpAndSettle();

      expect(find.text('Teacher ID'), findsOneWidget);
      expect(find.text('Lecturer'), findsOneWidget);
      expect(find.text('Stage'), findsNothing);
    });

    testWidgets('an account with no profile skips the section entirely',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(const User(
        id: 1,
        userId: 'admin',
        name: 'System Administrator',
        role: UserRole.admin,
      )));
      await tester.pumpAndSettle();

      // An empty card headed "Academic record" would be worse than no card.
      expect(find.text('Academic record'), findsNothing);
      expect(find.text('Administrator'), findsOneWidget);
    });
  });

  group('the two things you can do', () {
    testWidgets('both actions are reachable', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_change_password')), findsOneWidget);
      expect(find.byKey(const Key('profile_sign_out')), findsOneWidget);
    });

    testWidgets('signing out asks first', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_sign_out')));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.textContaining('user ID and password'), findsWidgets);
    });

    testWidgets('changing the password says what it costs before you tap',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      expect(find.text('Signs you out on every other device'), findsOneWidget);
    });
  });

  group('the developer info', () {
    testWidgets('an icon on the profile reveals who wrote it', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('developer_info')), findsOneWidget);
      // Behind the icon, not on the screen: it should not take room from the account.
      expect(find.text('Himel Sarder'), findsNothing);

      await tester.tap(find.byKey(const Key('developer_info')));
      await tester.pumpAndSettle();

      expect(find.text('Himel Sarder'), findsOneWidget);
      expect(find.textContaining('2021-22'), findsOneWidget);
      expect(find.textContaining('CSE'), findsWidgets);
      // No contact number: the card names the author, it is not a way to reach them.
      expect(find.textContaining('019'), findsNothing);
    });

    testWidgets('a teacher sees the same thing', (tester) async {
      // The answer does not depend on who is asking.
      tall(tester);
      await tester.pumpWidget(wrap(teacher()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('developer_info')));
      await tester.pumpAndSettle();

      expect(find.text('Himel Sarder'), findsOneWidget);
    });

    testWidgets('and so does an admin', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(admin()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('developer_info')));
      await tester.pumpAndSettle();

      expect(find.text('Himel Sarder'), findsOneWidget);
    });

    testWidgets('it closes again', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(student()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('developer_info')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('developer_info_dialog')), findsNothing);
    });
  });
}
