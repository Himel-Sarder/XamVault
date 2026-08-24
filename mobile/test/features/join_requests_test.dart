import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/features/teacher/join_requests_screen.dart';
import 'package:uniexam/models/student_exam.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeExamRepository exams}) {
  return ProviderScope(
    overrides: [examRepositoryProvider.overrideWithValue(exams)],
    child: MaterialApp(home: child),
  );
}

/// The bulk bar and the confirmation dialog both carry an "Approve all" button, so a
/// bare label finder is ambiguous. Always tap the dialog's.
Finder dialogButton(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, label),
    );

void main() {
  testWidgets('lists who asked, with their student number', (tester) async {
    final exams = FakeExamRepository()
      ..joinRequests = [buildJoinRequest(id: 1, name: 'Demo Student', userId: '20261234')];

    await tester.pumpWidget(wrap(const JoinRequestsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Demo Student'), findsOneWidget);
    expect(find.text('20261234'), findsOneWidget);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('1 pending'), findsOneWidget);
  });

  testWidgets('says so when nobody has asked yet', (tester) async {
    await tester.pumpWidget(
      wrap(const JoinRequestsScreen(examId: 10), exams: FakeExamRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('No requests yet'), findsOneWidget);
  });

  testWidgets('approving one request updates it in place', (tester) async {
    final exams = FakeExamRepository()..joinRequests = [buildJoinRequest(id: 1)];

    await tester.pumpWidget(wrap(const JoinRequestsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve_1')));
    await tester.pumpAndSettle();

    expect(exams.reviewed, [(1, true)]);
    expect(find.text('Approved'), findsOneWidget);
    // Once decided, the buttons go away.
    expect(find.byKey(const Key('approve_1')), findsNothing);
  });

  testWidgets('rejecting one request updates it in place', (tester) async {
    final exams = FakeExamRepository()..joinRequests = [buildJoinRequest(id: 1)];

    await tester.pumpWidget(wrap(const JoinRequestsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reject_1')));
    await tester.pumpAndSettle();

    expect(exams.reviewed, [(1, false)]);
    expect(find.text('Not approved'), findsOneWidget);
  });

  testWidgets('decided requests are listed but offer no buttons', (tester) async {
    final exams = FakeExamRepository()
      ..joinRequests = [
        buildJoinRequest(id: 1, status: JoinRequestStatus.approved, name: 'Already In'),
      ];

    await tester.pumpWidget(wrap(const JoinRequestsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    expect(find.text('Already In'), findsOneWidget);
    expect(find.byKey(const Key('approve_1')), findsNothing);
    expect(find.text('1 pending'), findsNothing, reason: 'nothing is pending');
  });

  testWidgets('approve all confirms first, then sends only the visible ids',
      (tester) async {
    final exams = FakeExamRepository()
      ..joinRequests = [
        buildJoinRequest(id: 1, name: 'First'),
        buildJoinRequest(id: 2, name: 'Second'),
      ];

    await tester.pumpWidget(wrap(const JoinRequestsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();
    expect(find.text('2 pending'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve_all')));
    await tester.pumpAndSettle();
    expect(find.text('Approve all pending?'), findsOneWidget);
    expect(find.textContaining('2 requests will be approved'), findsOneWidget);

    await tester.tap(dialogButton('Approve all'));
    await tester.pumpAndSettle();

    expect(exams.bulkReviews, hasLength(1));
    final (approve, ids) = exams.bulkReviews.single;
    expect(approve, isTrue);
    // Scoped to what was on screen, so a request that arrived since is left alone.
    expect(ids, [1, 2]);
    expect(find.text('Approved'), findsNWidgets(2));
  });

  testWidgets('cancelling the bulk dialog changes nothing', (tester) async {
    final exams = FakeExamRepository()..joinRequests = [buildJoinRequest(id: 1)];

    await tester.pumpWidget(wrap(const JoinRequestsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(exams.bulkReviews, isEmpty);
    expect(find.text('Awaiting approval'), findsOneWidget);
  });

  testWidgets('reject all is offered too', (tester) async {
    final exams = FakeExamRepository()..joinRequests = [buildJoinRequest(id: 1)];

    await tester.pumpWidget(wrap(const JoinRequestsScreen(examId: 10), exams: exams));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reject_all')));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('Reject all'));
    await tester.pumpAndSettle();

    expect(exams.bulkReviews.single.$1, isFalse);
    expect(find.text('Not approved'), findsOneWidget);
  });
}
