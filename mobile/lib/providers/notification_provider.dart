import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/notification.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

/// The caller's notifications, newest first.
final notificationsProvider =
    FutureProvider.autoDispose.family<List<AppNotification>, bool>((ref, unreadOnly) async {
  ref.watch(authProvider.select((state) => state.user?.id));
  final page = await ref
      .watch(notificationRepositoryProvider)
      .list(unreadOnly: unreadOnly);
  return page.items;
});

/// Just the badge number. Kept separate from the list so a dashboard can show a count
/// without loading every notification.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(authProvider.select((state) => state.user?.id));
  return ref.watch(notificationRepositoryProvider).unreadCount();
});

/// Both views go stale together whenever anything is read.
void refreshNotifications(WidgetRef ref) {
  ref.invalidate(notificationsProvider);
  ref.invalidate(unreadCountProvider);
}
