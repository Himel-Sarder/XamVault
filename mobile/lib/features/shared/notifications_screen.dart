import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/config/semantic_colours.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/models/notification.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/notification_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Everything that has happened, addressed to the person reading it (§61).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      try {
        await ref.read(notificationRepositoryProvider).markRead(notification.id);
        refreshNotifications(ref);
      } on ApiException {
        // Marking it read is a convenience; failing to must not block navigation.
      }
    }
    if (!mounted) return;

    // Where a tap leads depends on who is reading it: the same exam id means the
    // teacher's exam screen and the student's exam details.
    final examId = notification.examId;
    if (examId == null) return;
    final isStudent = ref.read(authProvider).user?.role == UserRole.student;
    context.push(
      isStudent ? Routes.studentExam(examId) : Routes.teacherExam(examId),
    );
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      refreshNotifications(ref);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _delete(AppNotification notification) async {
    try {
      await ref.read(notificationRepositoryProvider).delete(notification.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification removed.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) refreshNotifications(ref);
    }
  }

  Future<void> _clearRead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear read notifications?'),
        // Said plainly, because "clear" could otherwise be read as "clear everything".
        content: const Text(
          'Anything you have not read yet is kept. This only removes the notification, '
          'never the exam or result it was about.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    try {
      final cleared = await ref.read(notificationRepositoryProvider).clearRead();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cleared == 0
                  ? 'Nothing to clear.'
                  : 'Cleared $cleared notification${cleared == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) refreshNotifications(ref);
    }
  }

  /// Swipe to remove. No confirmation: a notification is a copy of news, so the worst
  /// case is losing a pointer to something still sitting where it was.
  Widget _dismissible(AppNotification notification) {
    return Dismissible(
      key: Key('dismiss_${notification.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: context.status.danger.container,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: context.status.danger.foreground),
      ),
      onDismissed: (_) => _delete(notification),
      child: _tile(notification),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider(_unreadOnly));
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            key: const Key('toggle_unread_only'),
            tooltip: _unreadOnly ? 'Show all' : 'Show unread only',
            onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
            icon: Icon(_unreadOnly ? Icons.filter_alt : Icons.filter_alt_outlined),
          ),
          if (unread > 0)
            TextButton(
              key: const Key('mark_all_read'),
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          IconButton(
            key: const Key('clear_read'),
            tooltip: 'Clear read',
            onPressed: _clearRead,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load notifications.',
          onRetry: () => refreshNotifications(ref),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyView(
              title: _unreadOnly ? 'Nothing unread' : 'Nothing yet',
              subtitle: _unreadOnly
                  ? 'You are up to date.'
                  : 'Exams, requests and results will show up here.',
              icon: Icons.notifications_none,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => refreshNotifications(ref),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _dismissible(items[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _tile(AppNotification notification) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The category's own colour, so a rejection and a result do not arrive looking
    // identical. A read notification keeps the hue but drops the fill, which is enough
    // to tell the two apart without repainting the row grey.
    final tint = notification.category.colour(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 92,
            color: notification.isRead ? Colors.transparent : tint.foreground,
          ),
          Expanded(
            child: ListTile(
        key: Key('notification_${notification.id}'),
        onTap: () => _open(notification),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: notification.isRead
                ? scheme.surfaceContainerHigh
                : tint.container,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            notification.category.icon,
            size: 20,
            color: notification.isRead ? scheme.onSurfaceVariant : tint.foreground,
          ),
        ),
        title: Text(
          notification.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(notification.body),
            const SizedBox(height: 4),
            Text(
              formatDateTime(notification.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: notification.examId == null ? null : const Icon(Icons.chevron_right),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bell with an unread count, for the dashboards.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      key: const Key('notification_bell'),
      tooltip: unread == 0 ? 'Notifications' : '$unread unread',
      onPressed: () => context.push(Routes.notifications),
      icon: Badge(
        // Badge.count renders "99+" past its max, so a busy inbox stays readable.
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        backgroundColor: scheme.error,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
