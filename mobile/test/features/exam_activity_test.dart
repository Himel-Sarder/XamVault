import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/exam_activity_screen.dart';
import 'package:uniexam/models/security_summary.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(FakeExamRepository exams) {
  return ProviderScope(
    overrides: [examRepositoryProvider.overrideWithValue(exams)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const ExamActivityScreen(examId: 10),
    ),
  );
}

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

StudentSecuritySummary row({
  int attemptId = 1,
  String name = 'Demo Student',
  int exits = 0,
  int secondsAway = 0,
  int longestAway = 0,
  int unreturned = 0,
  int screenshots = 0,
  int warnings = 0,
  int critical = 0,
  String? lockdown,
}) =>
    StudentSecuritySummary(
      attemptId: attemptId,
      studentId: 50 + attemptId,
      studentName: name,
      studentNumber: '2026$attemptId',
      exits: exits,
      secondsAway: secondsAway,
      longestAwaySeconds: longestAway,
      unreturnedExits: unreturned,
      screenshotAttempts: screenshots,
      screenRecordings: 0,
      timeChanges: 0,
      restarts: 0,
      totalEvents: exits * 2 + screenshots,
      warnings: warnings,
      critical: critical,
      lockdown: lockdown,
    );

FakeExamRepository withRows(List<StudentSecuritySummary> rows) =>
    FakeExamRepository()
      ..summary = ExamSecuritySummary(
        examId: 10,
        examTitle: 'Mid Term Quiz',
        students: rows,
      );

void main() {
  group('the exit record', () {
    testWidgets('each student shows how many times they left', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([
        row(name: 'Ayesha', exits: 3, secondsAway: 95, longestAway: 60),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('Ayesha'), findsOneWidget);
      // The count and its unit are stacked in the badge, so they are separate widgets.
      expect(find.text('3'), findsWidgets);
      expect(find.text('exits'), findsOneWidget);
    });

    testWidgets('time away is readable, not a raw second count', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([
        row(exits: 1, secondsAway: 95, longestAway: 95),
      ])));
      await tester.pumpAndSettle();

      expect(find.textContaining('1m 35s away'), findsOneWidget);
    });

    testWidgets('a student who never left says so plainly', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([row(name: 'Quiet Student')])));
      await tester.pumpAndSettle();

      expect(find.text('Stayed in the app throughout'), findsOneWidget);
    });

    testWidgets('an exit with no return is called out separately', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([
        row(exits: 2, secondsAway: 30, unreturned: 1),
      ])));
      await tester.pumpAndSettle();

      // It carries no duration, so without this it would read as no time away at all.
      expect(find.textContaining('did not return'), findsOneWidget);
    });

    testWidgets('the detail opens on tap', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([
        row(exits: 2, secondsAway: 40, longestAway: 30, screenshots: 1),
      ])));
      await tester.pumpAndSettle();

      expect(find.textContaining('Longest'), findsNothing);
      await tester.tap(find.byKey(const Key('activity_1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Longest 30s'), findsOneWidget);
      expect(find.textContaining('1 screenshot'), findsOneWidget);
    });
  });

  group('it reports, it does not accuse', () {
    testWidgets('the screen never uses the word cheating', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([
        row(exits: 9, secondsAway: 600, screenshots: 4, critical: 4),
      ])));
      await tester.pumpAndSettle();

      // §38. Every line here has an innocent explanation as well as a suspicious one,
      // and the platform is not the one to choose between them.
      for (final word in ['cheat', 'Cheat', 'cheating', 'suspicious', 'violation']) {
        expect(find.textContaining(word), findsNothing, reason: 'must not say "$word"');
      }
    });

    testWidgets('it says outright that this is a record, not a finding', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([row(exits: 1)])));
      await tester.pumpAndSettle();

      expect(find.textContaining('not a finding'), findsOneWidget);
      expect(find.textContaining('flat battery'), findsOneWidget);
    });
  });

  group('what the lockdown actually gave', () {
    testWidgets('an unprotected attempt is surfaced', (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([
        row(exits: 1, lockdown: 'Lock task unavailable: device is not provisioned'),
      ])));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('activity_1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('not provisioned'), findsOneWidget);
    });

    testWidgets('the overview counts devices that ran without protection',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(wrap(withRows([
        row(attemptId: 1, lockdown: 'Lock task unavailable: device is not provisioned'),
        row(attemptId: 2, name: 'Other', lockdown: 'Locked by device policy'),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('Ran unprotected'), findsOneWidget);
      // One of the two, and it is context for every other number on the screen.
      expect(find.text('1'), findsWidgets);
    });
  });

  testWidgets('an exam nobody sat explains itself', (tester) async {
    tall(tester);
    await tester.pumpWidget(wrap(withRows(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Nobody has sat this exam yet'), findsOneWidget);
  });
}
