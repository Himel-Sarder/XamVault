@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/shared/profile_screen.dart';
import 'package:uniexam/widgets/brand_mark.dart';

/// Renders the developer card so it can be looked at. Skipped by default.
void main() {
  testWidgets('developer info', (tester) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: DeveloperInfoDialog())),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/logo-xamv.png'),
        tester.element(find.byType(BrandLogo)),
      );
    });
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('developer_info.png'),
    );
  });
}
