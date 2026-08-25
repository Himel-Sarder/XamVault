import 'package:flutter/material.dart';

/// What happened. The category decides the icon and where a tap leads.
enum NotificationCategory {
  examPublished('exam_published', 'New exam', Icons.assignment_outlined),
  joinRequestReceived('join_request_received', 'Join request', Icons.how_to_reg_outlined),
  joinRequestApproved('join_request_approved', 'Approved', Icons.verified_outlined),
  joinRequestRejected('join_request_rejected', 'Not approved', Icons.cancel_outlined),
  examSubmitted('exam_submitted', 'Submitted', Icons.task_alt),
  resultPublished('result_published', 'Result', Icons.emoji_events_outlined),
  unknown('', 'Notification', Icons.notifications_outlined);

  const NotificationCategory(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  /// An unrecognised category is rendered generically rather than throwing — a server
  /// that learns a new event type must not break an app that has not been updated.
  static NotificationCategory fromJson(String value) =>
      NotificationCategory.values.firstWhere(
        (item) => item.wire == value,
        orElse: () => NotificationCategory.unknown,
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.payload,
    this.readAt,
  });

  final int id;
  final NotificationCategory category;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  /// A pointer for navigation — an exam id — not a copy of the record.
  final Map<String, dynamic>? payload;
  final DateTime? readAt;

  int? get examId => payload?['exam_id'] as int?;

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        category: category,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        payload: payload,
        readAt: readAt ?? this.readAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as int,
        category: NotificationCategory.fromJson(json['category'] as String),
        title: json['title'] as String,
        body: json['body'] as String,
        isRead: json['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}
