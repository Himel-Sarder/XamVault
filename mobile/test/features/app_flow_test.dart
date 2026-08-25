import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/core/token_store.dart';
import 'package:uniexam/main.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

/// A store that already holds a session, as it would after a previous sign-in.
Future<InMemoryTokenStore> storeWithSession() async {
  final store = InMemoryTokenStore();
  await store.write('uniexam.access_token', 'access-1');
  await store.write('uniexam.refresh_token', 'refresh-1');
  return store;
}

Widget app({
  required TokenStore store,
  required FakeAuthRepository auth,
  FakeCourseRepository? courses,
  FakeStudentRepository? student,
  FakeExamRepository? exams,
}) {
  return ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(auth),
      courseRepositoryProvider.overrideWithValue(courses ?? FakeCourseRepository()),
      // The student dashboard reads exams too; without this override it would reach for
      // a real network client and the assertions below would pass over a broken screen.
      studentRepositoryProvider.overrideWithValue(student ?? FakeStudentRepository()),
      examRepositoryProvider.overrideWithValue(exams ?? FakeExamRepository()),
    ],
    child: const UniExamApp(),
  );
}

void main() {
  testWidgets('with no stored session the app settles on the login screen', (tester) async {
    await tester.pumpWidget(
      app(store: InMemoryTokenStore(), auth: FakeAuthRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('University Examination Platform'), findsOneWidget);
  });

  testWidgets('a stored teacher session restores straight to the teacher dashboard',
      (tester) async {
    await tester.pumpWidget(
      app(store: await storeWithSession(), auth: FakeAuthRepository(user: teacherUser)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Teacher Dashboard'), findsOneWidget);
    expect(find.text('My Courses'), findsOneWidget);
    expect(find.text('CSE-301'), findsOneWidget);
    expect(find.text('Dr Demo Teacher'), findsOneWidget);
  });

  testWidgets('a stored student session restores to the student dashboard', (tester) async {
    await tester.pumpWidget(
      app(store: await storeWithSession(), auth: FakeAuthRepository(user: studentUser)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Student Dashboard'), findsOneWidget);
    expect(find.text('Enrolled Courses'), findsOneWidget);
    expect(find.textContaining('Student ID 20261234'), findsOneWidget);
    expect(find.text('Teacher Dashboard'), findsNothing);
    // Exams come first on a student's home: it is what they open the app for.
    expect(find.text('Available Exams'), findsOneWidget);
    expect(find.text('Mid Term Quiz'), findsOneWidget);
  });

  testWidgets('a revoked stored session falls back to login', (tester) async {
    // me() throws 401 because the fake has no user: the token was revoked while the app
    // was closed, which must not leave the user staring at an empty dashboard.
    await tester.pumpWidget(
      app(store: await storeWithSession(), auth: FakeAuthRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('an empty course list shows guidance rather than a blank screen',
      (tester) async {
    await tester.pumpWidget(
      app(
        store: await storeWithSession(),
        auth: FakeAuthRepository(user: studentUser),
        courses: FakeCourseRepository(courses: const []),
        student: FakeStudentRepository(exams: const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No courses yet'), findsOneWidget);
    expect(find.text('No exams right now'), findsOneWidget);
  });

  testWidgets('signing out from the profile returns to login', (tester) async {
    final auth = FakeAuthRepository(user: teacherUser);
    await tester.pumpWidget(app(store: await storeWithSession(), auth: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Lecturer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile_sign_out')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(auth.logoutCalls, 1, reason: 'the refresh token must be revoked server-side');
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the full course list is reachable from the dashboard', (tester) async {
    await tester.pumpWidget(
      app(store: await storeWithSession(), auth: FakeAuthRepository(user: teacherUser)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'My Courses'), findsOneWidget);
    expect(find.text('CSE-301'), findsOneWidget);
  });

  testWidgets('an admin session sees every course', (tester) async {
    const admin = User(id: 1, userId: 'admin', name: 'System Admin', role: UserRole.admin);
    await tester.pumpWidget(
      app(store: await storeWithSession(), auth: FakeAuthRepository(user: admin)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Administration'), findsOneWidget);
    expect(find.text('All Courses'), findsOneWidget);
  });
}
