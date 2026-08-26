<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/token_store.dart';
import 'package:uniexam/features/auth/login_screen.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget _wrap(FakeAuthRepository authRepository) {
  return ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      authRepositoryProvider.overrideWithValue(authRepository),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: LoginScreen()),
  );
}

void main() {
  testWidgets('shows validation errors for empty fields', (tester) async {
    final auth = FakeAuthRepository(user: teacherUser);
    await tester.pumpWidget(_wrap(auth));

    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();

    expect(find.text('Enter your user ID'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(auth.loginCalls, 0, reason: 'the request must not leave the device');
  });

  testWidgets('successful login moves the auth state to authenticated', (tester) async {
    final auth = FakeAuthRepository(user: teacherUser);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(theme: AppTheme.light(), home: LoginScreen());
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'Passw0rd!123');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(auth.loginCalls, 1);
    final state = container.read(authProvider);
    expect(state.isAuthenticated, isTrue);
    expect(state.user?.userId, 'T1001');
    // The token pair must have been persisted, not just held in the notifier.
    expect(container.read(tokenManagerProvider).accessToken, 'access-1');
  });

  testWidgets('login loads the full user record, not the compact login payload',
      (tester) async {
    // /auth/login returns only {id, user_id, name, role}. Stopping there left the app
    // with no department and no role profile until the next restart.
    final auth = FakeAuthRepository(user: teacherUser);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(theme: AppTheme.light(), home: LoginScreen());
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'Passw0rd!123');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    final user = container.read(authProvider).user;
    expect(user?.department?.code, 'CSE');
    expect(user?.teacherProfile?.designation, 'Lecturer');
  });

  testWidgets('a failed login leaves no tokens behind', (tester) async {
    final auth = FakeAuthRepository(
      failWith: const ApiException('Incorrect user ID or password', statusCode: 401),
    );
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(theme: AppTheme.light(), home: LoginScreen());
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'nope');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(container.read(tokenManagerProvider).hasSession, isFalse);
  });

  testWidgets('a rejected login shows the server message and stays put', (tester) async {
    final auth = FakeAuthRepository(
      failWith: const ApiException('Incorrect user ID or password', statusCode: 401),
    );
    await tester.pumpWidget(_wrap(auth));

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'wrong');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect user ID or password'), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('the password is obscured until revealed', (tester) async {
    await tester.pumpWidget(_wrap(FakeAuthRepository(user: teacherUser)));

    TextField passwordField() => tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('login_password')),
            matching: find.byType(TextField),
          ),
        );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });
}
=======
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/token_store.dart';
import 'package:uniexam/features/auth/login_screen.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget _wrap(FakeAuthRepository authRepository) {
  return ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      authRepositoryProvider.overrideWithValue(authRepository),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: LoginScreen()),
  );
}

void main() {
  testWidgets('shows validation errors for empty fields', (tester) async {
    final auth = FakeAuthRepository(user: teacherUser);
    await tester.pumpWidget(_wrap(auth));

    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();

    expect(find.text('Enter your user ID'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(auth.loginCalls, 0, reason: 'the request must not leave the device');
  });

  testWidgets('successful login moves the auth state to authenticated', (tester) async {
    final auth = FakeAuthRepository(user: teacherUser);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(theme: AppTheme.light(), home: LoginScreen());
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'Passw0rd!123');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(auth.loginCalls, 1);
    final state = container.read(authProvider);
    expect(state.isAuthenticated, isTrue);
    expect(state.user?.userId, 'T1001');
    // The token pair must have been persisted, not just held in the notifier.
    expect(container.read(tokenManagerProvider).accessToken, 'access-1');
  });

  testWidgets('login loads the full user record, not the compact login payload',
      (tester) async {
    // /auth/login returns only {id, user_id, name, role}. Stopping there left the app
    // with no department and no role profile until the next restart.
    final auth = FakeAuthRepository(user: teacherUser);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(theme: AppTheme.light(), home: LoginScreen());
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'Passw0rd!123');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    final user = container.read(authProvider).user;
    expect(user?.department?.code, 'CSE');
    expect(user?.teacherProfile?.designation, 'Lecturer');
  });

  testWidgets('a failed login leaves no tokens behind', (tester) async {
    final auth = FakeAuthRepository(
      failWith: const ApiException('Incorrect user ID or password', statusCode: 401),
    );
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(theme: AppTheme.light(), home: LoginScreen());
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'nope');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(container.read(tokenManagerProvider).hasSession, isFalse);
  });

  testWidgets('a rejected login shows the server message and stays put', (tester) async {
    final auth = FakeAuthRepository(
      failWith: const ApiException('Incorrect user ID or password', statusCode: 401),
    );
    await tester.pumpWidget(_wrap(auth));

    await tester.enterText(find.byKey(const Key('login_user_id')), 'T1001');
    await tester.enterText(find.byKey(const Key('login_password')), 'wrong');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect user ID or password'), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('the password is obscured until revealed', (tester) async {
    await tester.pumpWidget(_wrap(FakeAuthRepository(user: teacherUser)));

    TextField passwordField() => tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('login_password')),
            matching: find.byType(TextField),
          ),
        );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });
}
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
