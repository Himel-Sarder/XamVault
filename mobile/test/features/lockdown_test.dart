import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/exam_security.dart';
import 'package:uniexam/features/student/exam_attempt_screen.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(
  Widget child, {
  required FakeStudentRepository student,
  required FakeExamSecurity security,
}) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(student),
      examSecurityProvider.overrideWithValue(security),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('engaging lockdown', () {
    testWidgets('a secure exam asks the device to lock down', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true);
      final security = FakeExamSecurity();

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();

      expect(security.enterCalls, 1);
      expect(security.listening, isTrue);
    });

    testWidgets('an exam without secure mode leaves the device alone', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: false);
      final security = FakeExamSecurity();

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();

      expect(security.enterCalls, 0);
      expect(find.byKey(const Key('lockdown_banner')), findsNothing);
    });
  });

  group('telling the student the truth', () {
    testWidgets('screen pinning is described as dismissible, not as a lock',
        (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true);
      // The unmanaged-phone case: pinned, not locked by policy.
      final security = FakeExamSecurity();

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lockdown_banner')), findsOneWidget);
      expect(find.textContaining('Screenshots are blocked'), findsOneWidget);
      expect(find.textContaining('Device locked to this exam'), findsNothing);
    });

    testWidgets('a genuinely locked device says so', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true);
      final security = FakeExamSecurity(
        status: const LockdownStatus(
          secureFlag: true,
          immersive: true,
          lockTask: true,
          lockTaskIsPinning: false,
          detail: 'Locked by device policy',
        ),
      );

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Device locked to this exam'), findsOneWidget);
    });

    testWidgets('a platform without lockdown says that plainly', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true);
      final security = FakeExamSecurity(supported: false);

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('not available here'), findsOneWidget);
      expect(find.textContaining('still recorded'), findsOneWidget);
    });
  });

  group('reporting what happened', () {
    testWidgets('the outcome of the lockdown attempt is itself reported', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true);
      final security = FakeExamSecurity(supported: false);

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      // A teacher reading the trail can see the exam ran without device protection.
      expect(
        student.reportedEvents.map((event) => event.eventType),
        contains('LOCKDOWN_UNAVAILABLE'),
      );
    });

    testWidgets('observations from the device are batched and sent', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true);
      final security = FakeExamSecurity();

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();
      student.reportedEvents.clear();

      security.emit(const SecurityObservation('APP_BACKGROUND'));
      security.emit(const SecurityObservation('APP_FOREGROUND', {'away_ms': 4200}));
      await tester.pump(const Duration(milliseconds: 500));
      expect(student.reportedEvents, isEmpty, reason: 'still batching');

      await tester.pump(const Duration(seconds: 3));
      expect(
        student.reportedEvents.map((event) => event.eventType),
        containsAll(['APP_BACKGROUND', 'APP_FOREGROUND']),
      );
    });

    testWidgets('a failed report never interrupts the exam', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true)
        ..failSecurityReports = true;
      final security = FakeExamSecurity();

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();
      security.emit(const SecurityObservation('APP_BACKGROUND'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // The paper is still there and still answerable.
      expect(find.text('Question 1 of 3'), findsOneWidget);
      expect(find.byKey(const Key('submit_exam')), findsOneWidget);
    });

    testWidgets('submitting releases the device', (tester) async {
      useTallSurface(tester);
      final student = FakeStudentRepository()
        ..currentAttempt = buildAttempt(secureMode: true);
      final security = FakeExamSecurity();

      await tester.pumpWidget(wrap(
        const ExamAttemptScreen(attemptId: 900),
        student: student,
        security: security,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_exam')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Submit this exam?'), findsOneWidget, reason: 'dialog should open');
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      // Explicit pumps rather than pumpAndSettle: the countdown is still ticking, so
      // settling would never finish. Several turns let the release chain complete.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      expect(student.submitCalls, 1);
      // A student must never be left pinned inside a finished exam. What the closing
      // screen then renders is attempt_flow_test's business, not this test's.
      expect(security.exitCalls, 1);
    });
  });
}
