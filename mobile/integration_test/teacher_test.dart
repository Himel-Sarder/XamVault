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
  testWidgets('the profile shows server-supplied details and signs out', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await _signIn(tester, demoStudentId, demoPassword);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    // Department comes from the /auth/me join, so this proves the nested payload parses.
    expect(find.textContaining('Computer Science & Engineering'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile_sign_out')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle(const Duration(seconds: 15));

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the teacher sees who asked to sit the exam', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await _signIn(tester, demoTeacherId, demoPassword);

    await tester.tap(find.text('CSE-301').first);
    await tester.pumpAndSettle(const Duration(seconds: 15));
    await tester.tap(find.text('API Smoke Exam').first);
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // A published exam is frozen, and its join requests are reachable from here.
    expect(find.textContaining('questions are frozen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('join_requests_row')));
    await tester.pumpAndSettle(const Duration(seconds: 15));

    expect(find.text('Join Requests'), findsOneWidget);
    expect(find.text('Demo Student'), findsOneWidget);
  });

  testWidgets('the teacher sees the cohort marks and that they are released',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await _signIn(tester, demoTeacherId, demoPassword);

    await tester.tap(find.text('CSE-301').first);
    await tester.pumpAndSettle(const Duration(seconds: 20));
    await tester.tap(find.text('Live Attempt Exam').first);
    await tester.pumpAndSettle(const Duration(seconds: 20));

    await tester.tap(find.byKey(const Key('results_row')));
    await tester.pumpAndSettle(const Duration(seconds: 20));

    expect(find.text('Results'), findsWidgets);
    expect(find.text('Demo Student'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    // Already released, so there is nothing left to release.
    expect(find.byKey(const Key('publish_results')), findsNothing);
  });
}
