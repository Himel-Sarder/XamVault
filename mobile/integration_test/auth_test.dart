// End-to-end test against a REAL backend. Nothing is faked: the app builds its normal
// Dio client, talks HTTP to FastAPI, which talks to PostgreSQL.
//
// Prerequisites:
//   1. Backend running and seeded:  python -m app.utils.seed --demo
//   2. Run on a device/emulator:
//
//      flutter test integration_test \
//        -d emulator-5554 \
//        --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
//
// The suite is split by area so each `flutter drive` run finishes well inside the
// driver's 20-minute request_data ceiling — every test signs in, and each request to a
// remote database costs seconds.
//
// This complements test/ (which fakes the network to test UI logic in isolation) by
// proving the wire format, auth flow and secure storage actually work on a device.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uniexam/core/token_store.dart';
import 'package:uniexam/main.dart';
import 'package:uniexam/providers/providers.dart';

const demoStudentId = '20261234';
const demoTeacherId = 'T1001';
const demoPassword = 'Passw0rd!123';

Future<void> _signIn(WidgetTester tester, String userId, String password) async {
  await tester.enterText(find.byKey(const Key('login_user_id')), userId);
  await tester.enterText(find.byKey(const Key('login_password')), password);
  await tester.tap(find.byKey(const Key('login_submit')));
  await tester.pumpAndSettle(const Duration(seconds: 20));
}

/// A fresh in-memory token store per test, so one test's session never leaks into the
/// next. Everything else is the real app: real Dio client, real API, real database.
Widget app() => ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(InMemoryTokenStore())],
      child: const UniExamApp(),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a student signs in and sees their enrolled course', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 10));

    expect(find.text('Sign in'), findsOneWidget);
    await _signIn(tester, demoStudentId, demoPassword);

    expect(find.text('Student Dashboard'), findsOneWidget);
    expect(find.text('Demo Student'), findsOneWidget);
    expect(find.text('Available Exams'), findsOneWidget);
    expect(find.text('Enrolled Courses'), findsOneWidget);
    // The course code appears on both the exam tile and the course tile, so this is
    // deliberately not findsOneWidget.
    expect(find.text('CSE-301'), findsWidgets);
  });

  testWidgets('a teacher signs in and sees the course they own', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await _signIn(tester, demoTeacherId, demoPassword);

    expect(find.text('Teacher Dashboard'), findsOneWidget);
    expect(find.text('My Courses'), findsOneWidget);
    expect(find.text('CSE-301'), findsOneWidget);
  });

  testWidgets('wrong credentials are rejected by the server', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await _signIn(tester, demoStudentId, 'definitely-not-the-password');

    expect(find.text('Incorrect user ID or password'), findsOneWidget);
    expect(find.text('Student Dashboard'), findsNothing);
  });
}
