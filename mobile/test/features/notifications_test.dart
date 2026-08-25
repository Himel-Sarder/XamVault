import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/shared/notifications_screen.dart';
import 'package:uniexam/models/notification.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

Widget wrap(Widget child, {required FakeNotificationRepository notifications}) {
  return ProviderScope(
    overrides: [notificationRepositoryProvider.overrideWithValue(notifications)],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('the inbox', () {
    testWidgets('shows a notification with its body and time', (tester) async {
      useTallSurface(tester);
      final repo = FakeNotificationRepository(notifications: [
        buildNotification(title: 'New exam: Mid Term Quiz', body: 'CSE-301 — 30 minutes.'),
      ]);

      await tester.pumpWidget(wrap(const NotificationsScreen(), notifications: repo));
      await tester.pumpAndSettle();

      expect(find.text('New exam: Mid Term Quiz'), findsOneWidget);
      expect(find.text('CSE-301 — 30 minutes.'), findsOneWidget);
      expect(find.textContaining('24 Aug 2026'), findsOneWidget);
    });

    testWidgets('an empty inbox says what will appear there', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(const NotificationsScreen(),
            notifications: FakeNotificationRepository(notifications: [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing yet'), findsOneWidget);
      expect(find.textContaining('Exams, requests and results'), findsOneWidget);
    });

    testWidgets('the unread filter hides what has been seen', (tester) async {
      useTallSurface(tester);
      final repo = FakeNotificationRepository(notifications: [
        buildNotification(id: 1, title: 'Unread one', isRead: false),
        buildNotification(id: 2, title: 'Already seen', isRead: true),
      ]);

      await tester.pumpWidget(wrap(const NotificationsScreen(), notifications: repo));
      await tester.pumpAndSettle();
      expect(find.text('Already seen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle_unread_only')));
      await tester.pumpAndSettle();

      expect(repo.lastUnreadOnly, isTrue);
      expect(find.text('Already seen'), findsNothing);
      expect(find.text('Unread one'), findsOneWidget);
    });

    testWidgets('an unrecognised category still renders', (tester) async {
      useTallSurface(tester);
      // A server that learns a new event type must not break an older app.
      final repo = FakeNotificationRepository(notifications: [
        buildNotification(category: NotificationCategory.unknown, title: 'Something new'),
      ]);

      await tester.pumpWidget(wrap(const NotificationsScreen(), notifications: repo));
      await tester.pumpAndSettle();

      expect(find.text('Something new'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsWidgets);
    });
  });

  group('reading', () {
    testWidgets('opening a notification marks it read', (tester) async {
      useTallSurface(tester);
      final repo = FakeNotificationRepository(notifications: [
        buildNotification(id: 42, examId: null),
      ]);

      await tester.pumpWidget(wrap(const NotificationsScreen(), notifications: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_42')));
      await tester.pumpAndSettle();

      expect(repo.readIds, [42]);
    });

    testWidgets('an already-read notification is not marked again', (tester) async {
      useTallSurface(tester);
      final repo = FakeNotificationRepository(notifications: [
        buildNotification(id: 42, isRead: true, examId: null),
      ]);

      await tester.pumpWidget(wrap(const NotificationsScreen(), notifications: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_42')));
      await tester.pumpAndSettle();

      expect(repo.readIds, isEmpty);
    });

    testWidgets('mark all read is offered only while something is unread',
        (tester) async {
      useTallSurface(tester);
      final repo = FakeNotificationRepository(notifications: [buildNotification(id: 1)]);

      await tester.pumpWidget(wrap(const NotificationsScreen(), notifications: repo));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mark_all_read')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mark_all_read')));
      await tester.pumpAndSettle();

      expect(repo.markAllCalls, 1);
      expect(find.byKey(const Key('mark_all_read')), findsNothing);
    });

    testWidgets('a failure to load is reported, not swallowed', (tester) async {
      useTallSurface(tester);
      final repo = FakeNotificationRepository()
        ..failWith = const ApiException('Could not reach the server', statusCode: 503);

      await tester.pumpWidget(wrap(const NotificationsScreen(), notifications: repo));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server'), findsOneWidget);
    });
  });

  group('the bell', () {
    testWidgets('carries the unread count', (tester) async {
      final repo = FakeNotificationRepository(notifications: [
        buildNotification(id: 1, isRead: false),
        buildNotification(id: 2, isRead: false),
        buildNotification(id: 3, isRead: true),
      ]);

      await tester.pumpWidget(
        wrap(const Scaffold(appBar: null, body: NotificationBell()), notifications: repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows no badge when everything is read', (tester) async {
      final repo = FakeNotificationRepository(notifications: [
        buildNotification(id: 1, isRead: true),
      ]);

      await tester.pumpWidget(
        wrap(const Scaffold(body: NotificationBell()), notifications: repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('0'), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });
  });
}
