<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/analytics_screen.dart';
import 'package:uniexam/models/analytics.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeExamRepository exams}) {
  return ProviderScope(
    overrides: [examRepositoryProvider.overrideWithValue(exams)],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows the cohort and the score summary', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Analytics Paper'), findsOneWidget);
    expect(find.text('Who sat it'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('33.3%'), findsWidgets, reason: 'average and median');
    expect(find.text('66.7%'), findsWidgets, reason: 'highest');
  });

  testWidgets('an exam nobody has sat says so instead of showing zero', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository()
      ..analyticsResult = buildAnalytics(
        approved: 2,
        submitted: 0,
        absent: 2,
        scores: const ScoreSummary(),
        passed: 0,
        failed: 0,
        passRate: null,
        distribution: const [
          DistributionBucket(label: '0-20%', count: 0),
          DistributionBucket(label: '81-100%', count: 0),
        ],
      );

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    // "0%" would read as "everyone failed" rather than "nobody has sat it".
    expect(find.text('Nobody has submitted this exam yet.'), findsOneWidget);
    expect(find.text('No submissions to measure yet.'), findsOneWidget);
  });

  testWidgets('the pass threshold is adjustable and re-queried', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('At or above 40%'), findsOneWidget);
    expect(exams.analyticsThresholds.first, 40.0);

    await tester.drag(find.byKey(const Key('pass_threshold')), const Offset(200, 0));
    await tester.pumpAndSettle();

    // The threshold is the university's policy, so moving it re-asks the server rather
    // than recomputing locally from figures it does not have.
    expect(exams.analyticsThresholds.length, greaterThan(1));
    expect(exams.analyticsThresholds.last, greaterThan(40.0));
  });

  testWidgets('the distribution renders one row per band', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const AnalyticsScreen(examId: 10), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Score distribution'), findsOneWidget);
    expect(find.text('0-20%'), findsOneWidget);
    expect(find.text('61-80%'), findsOneWidget);
  });

  testWidgets('a choice question shows accuracy', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const AnalyticsScreen(examId: 10), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Correct 2 · Wrong 0 · Skipped 1'), findsOneWidget);
  });

  testWidgets('a written question shows marking progress, not accuracy', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const AnalyticsScreen(examId: 10), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 still to mark'), findsOneWidget);
  });

  testWidgets('a fully marked written question shows its average', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository()
      ..analyticsResult = buildAnalytics(questions: const [
        QuestionAnalytics(
          examQuestionId: 103,
          position: 3,
          type: 'SHORT_ANSWER',
          questionText: 'Q3 explain',
          marks: 10,
          isAutoMarked: false,
          answered: 2,
          skipped: 1,
          awaitingMarks: 0,
          averageMarks: 6,
        ),
      ]);

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Average 6.0 of 10'), findsOneWidget);
  });
}
=======
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/analytics_screen.dart';
import 'package:uniexam/models/analytics.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeExamRepository exams}) {
  return ProviderScope(
    overrides: [examRepositoryProvider.overrideWithValue(exams)],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows the cohort and the score summary', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Analytics Paper'), findsOneWidget);
    expect(find.text('Who sat it'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('33.3%'), findsWidgets, reason: 'average and median');
    expect(find.text('66.7%'), findsWidgets, reason: 'highest');
  });

  testWidgets('an exam nobody has sat says so instead of showing zero', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository()
      ..analyticsResult = buildAnalytics(
        approved: 2,
        submitted: 0,
        absent: 2,
        scores: const ScoreSummary(),
        passed: 0,
        failed: 0,
        passRate: null,
        distribution: const [
          DistributionBucket(label: '0-20%', count: 0),
          DistributionBucket(label: '81-100%', count: 0),
        ],
      );

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    // "0%" would read as "everyone failed" rather than "nobody has sat it".
    expect(find.text('Nobody has submitted this exam yet.'), findsOneWidget);
    expect(find.text('No submissions to measure yet.'), findsOneWidget);
  });

  testWidgets('the pass threshold is adjustable and re-queried', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository();

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('At or above 40%'), findsOneWidget);
    expect(exams.analyticsThresholds.first, 40.0);

    await tester.drag(find.byKey(const Key('pass_threshold')), const Offset(200, 0));
    await tester.pumpAndSettle();

    // The threshold is the university's policy, so moving it re-asks the server rather
    // than recomputing locally from figures it does not have.
    expect(exams.analyticsThresholds.length, greaterThan(1));
    expect(exams.analyticsThresholds.last, greaterThan(40.0));
  });

  testWidgets('the distribution renders one row per band', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const AnalyticsScreen(examId: 10), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Score distribution'), findsOneWidget);
    expect(find.text('0-20%'), findsOneWidget);
    expect(find.text('61-80%'), findsOneWidget);
  });

  testWidgets('a choice question shows accuracy', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const AnalyticsScreen(examId: 10), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Correct 2 · Wrong 0 · Skipped 1'), findsOneWidget);
  });

  testWidgets('a written question shows marking progress, not accuracy', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      wrap(const AnalyticsScreen(examId: 10), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 still to mark'), findsOneWidget);
  });

  testWidgets('a fully marked written question shows its average', (tester) async {
    useTallSurface(tester);
    final exams = FakeExamRepository()
      ..analyticsResult = buildAnalytics(questions: const [
        QuestionAnalytics(
          examQuestionId: 103,
          position: 3,
          type: 'SHORT_ANSWER',
          questionText: 'Q3 explain',
          marks: 10,
          isAutoMarked: false,
          answered: 2,
          skipped: 1,
          awaitingMarks: 0,
          averageMarks: 6,
        ),
      ]);

    await tester.pumpWidget(wrap(const AnalyticsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Average 6.0 of 10'), findsOneWidget);
  });
}
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
