@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/brand_mark.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Not an assertion suite -- it renders the brand surfaces so they can be looked at.
/// Run with `flutter test test/golden --update-goldens` to refresh the images.
void main() {
  testWidgets('splash mid-entrance and at rest', (tester) async {
    tester.view.physicalSize = const Size(450, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const DecoratedBox(
          decoration: BoxDecoration(gradient: BrandColours.field),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandLogo(size: 116),
                SizedBox(height: 28),
                Text(
                  'XamVault',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 44),
                VaultDial(size: 44, colour: BrandColours.accentBright),
              ],
            ),
          ),
        ),
      ),
    );
    // Asset decoding is genuinely asynchronous, and the test binding does not run real
    // async work unless asked. Without this the logo silently never appears -- which is
    // exactly the failure a preview is meant to catch.
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/logo-xamv.png'),
        tester.element(find.byType(BrandLogo)),
      );
    });
    // Not pumpAndSettle: the dial repeats forever and would never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('splash.png'),
    );
  });

  testWidgets('the loading view', (tester) async {
    tester.view.physicalSize = const Size(350, 250);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: LoadingView(message: 'Loading your courses')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('loading.png'));
  });

  testWidgets('the sign-in header and a working button', (tester) async {
    tester.view.physicalSize = const Size(450, 450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: BrandColours.field,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const BrandLogo(size: 68),
                ),
                const SizedBox(height: 32),
                // The case that was blue-on-blue before: a spinner inside a filled
                // button, taking its colour from the button rather than the scheme.
                FilledButton.icon(
                  onPressed: () {},
                  icon: const SizedBox(
                    width: 18,
                    height: 18,
                    child: InlineLoader(size: 18),
                  ),
                  label: const Text('Signing in...'),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const InlineLoader(size: 16),
                  label: const Text('Saving'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/logo-xamv.png'),
        tester.element(find.byType(BrandLogo)),
      );
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('signin.png'));
  });
}
