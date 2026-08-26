import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/auth/login_screen.dart';
import 'package:uniexam/features/shared/splash_screen.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

void main() {
  group('a host that sleeps', () {
    test('the timeout is longer than a cold start', () {
      // A free Render instance spins down after ~15 minutes and takes roughly 40
      // seconds to come back. The old 15s/20s ceilings meant the first request after
      // a quiet spell could never succeed, and the app blamed the network for it.
      expect(AppConfig.connectTimeout.inSeconds, greaterThan(45));
      expect(AppConfig.receiveTimeout.inSeconds, greaterThan(45));
    });

    test('the hint appears well before the request gives up', () {
      // Otherwise the explanation arrives after the failure it was meant to explain.
      expect(AppConfig.wakeHintAfter, lessThan(AppConfig.connectTimeout));
    });

    test('health is addressed at the server root, not under the API prefix', () {
      expect(AppConfig.healthUrl.endsWith('/health'), isTrue);
      expect(AppConfig.healthUrl.contains('/api/v1'), isFalse);
    });
  });

  group('the wait is explained', () {
    testWidgets('the splash nudges the server awake', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: AppTheme.light(), home: const SplashScreen()),
      ));
      await tester.pump();

      // Started while the user is still reading the splash, so the cold start overlaps
      // with something they were doing anyway.
      expect(auth.warmUpCalls, 1);
    });

    testWidgets('a quick start never mentions waking', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        child: MaterialApp(theme: AppTheme.light(), home: const SplashScreen()),
      ));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(const Key('wake_hint')), findsNothing);
    });

    testWidgets('a long wait says why', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        child: MaterialApp(theme: AppTheme.light(), home: const SplashScreen()),
      ));
      await tester.pump(AppConfig.wakeHintAfter + const Duration(seconds: 1));

      expect(find.byKey(const Key('wake_hint')), findsOneWidget);
      expect(find.textContaining('up to a minute'), findsOneWidget);
    });

    testWidgets('the login screen is silent until the wait is real', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
        child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wake_hint')), findsNothing);
    });
  });
}
