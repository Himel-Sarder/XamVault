import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/notification.dart';
import 'package:uniexam/models/paged.dart';

/// In-app notifications (§61). Scoped to the caller by the server, so there is nothing
/// to filter here.
class NotificationRepository {
  const NotificationRepository(this._api);

  final ApiClient _api;

  Future<Paged<AppNotification>> list({
    bool unreadOnly = false,
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/notifications',
      query: {'page': page, 'page_size': pageSize, 'unread_only': unreadOnly},
    );
    return Paged.fromJson(data, AppNotification.fromJson);
  }

  /// One indexed COUNT, cheap enough to refresh for a badge.
  Future<int> unreadCount() async {
    final data = await _api.get<Map<String, dynamic>>('/notifications/unread-count');
    return data['unread'] as int;
  }

  Future<AppNotification> markRead(int notificationId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/notifications/$notificationId/read',
    );
    return AppNotification.fromJson(data);
  }

  /// Removes one notification from your own inbox.
  ///
  /// Safe to delete outright, unlike most things in this app: a notification is a copy
  /// of news, not the news itself. Removing "your result is available" leaves the
  /// result exactly where it was.
  Future<void> delete(int id) => _api.delete('/notifications/$id');

  /// Clears the ones already seen, and only those.
  Future<int> clearRead() async {
    final data = await _api.deleteWithResult<Map<String, dynamic>>('/notifications/read');
    return data['cleared'] as int? ?? 0;
  }

  Future<int> markAllRead() async {
    final data = await _api.post<Map<String, dynamic>>('/notifications/read-all');
    return data['updated'] as int;
  }
}
