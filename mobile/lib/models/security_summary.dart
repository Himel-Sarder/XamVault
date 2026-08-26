/// One student's activity during an exam, as the device reported it.
///
/// A record, not a verdict (§38). Every field here has an innocent explanation as well
/// as a suspicious one — a call arrives, a parent walks in, the network drops — so the
/// UI counts and presents, and the teacher decides.
class StudentSecuritySummary {
  const StudentSecuritySummary({
    required this.attemptId,
    required this.studentId,
    required this.studentName,
    required this.exits,
    required this.secondsAway,
    required this.longestAwaySeconds,
    required this.unreturnedExits,
    required this.screenshotAttempts,
    required this.screenRecordings,
    required this.timeChanges,
    required this.restarts,
    required this.totalEvents,
    required this.warnings,
    required this.critical,
    this.studentNumber,
    this.lockdown,
  });

  final int attemptId;
  final int studentId;
  final String studentName;
  final String? studentNumber;

  /// How many times the app left the foreground.
  final int exits;
  final int secondsAway;
  final int longestAwaySeconds;

  /// Exits the app never returned from. These contribute no duration, so they are shown
  /// separately rather than quietly counting as nothing.
  final int unreturnedExits;

  final int screenshotAttempts;
  final int screenRecordings;
  final int timeChanges;
  final int restarts;

  final int totalEvents;
  final int warnings;
  final int critical;

  /// What protection the device actually granted. Context for everything else.
  final String? lockdown;

  bool get isQuiet => exits == 0 && warnings == 0 && critical == 0;

  /// Ran without the protection the exam asked for.
  bool get ranUnprotected {
    final detail = lockdown?.toLowerCase();
    if (detail == null) return false;
    return detail.contains('unavailable') || detail.contains('refused');
  }

  factory StudentSecuritySummary.fromJson(Map<String, dynamic> json) =>
      StudentSecuritySummary(
        attemptId: json['attempt_id'] as int,
        studentId: json['student_id'] as int,
        studentName: json['student_name'] as String,
        studentNumber: json['student_number'] as String?,
        exits: json['exits'] as int? ?? 0,
        secondsAway: json['seconds_away'] as int? ?? 0,
        longestAwaySeconds: json['longest_away_seconds'] as int? ?? 0,
        unreturnedExits: json['unreturned_exits'] as int? ?? 0,
        screenshotAttempts: json['screenshot_attempts'] as int? ?? 0,
        screenRecordings: json['screen_recordings'] as int? ?? 0,
        timeChanges: json['time_changes'] as int? ?? 0,
        restarts: json['restarts'] as int? ?? 0,
        totalEvents: json['total_events'] as int? ?? 0,
        warnings: json['warnings'] as int? ?? 0,
        critical: json['critical'] as int? ?? 0,
        lockdown: json['lockdown'] as String?,
      );
}

class ExamSecuritySummary {
  const ExamSecuritySummary({
    required this.examId,
    required this.examTitle,
    required this.students,
  });

  final int examId;
  final String examTitle;
  final List<StudentSecuritySummary> students;

  int get totalExits => students.fold(0, (sum, s) => sum + s.exits);
  int get studentsWhoLeft => students.where((s) => s.exits > 0).length;
  int get unprotected => students.where((s) => s.ranUnprotected).length;

  factory ExamSecuritySummary.fromJson(Map<String, dynamic> json) => ExamSecuritySummary(
        examId: json['exam_id'] as int,
        examTitle: json['exam_title'] as String,
        students: (json['students'] as List<dynamic>? ?? const [])
            .map((item) => StudentSecuritySummary.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One line of the trail for a single attempt.
class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.occurredAt,
    this.metadata,
  });

  final int id;
  final String eventType;
  final String severity;
  final DateTime occurredAt;
  final Map<String, dynamic>? metadata;

  /// Seconds the app was away, when this event carries that.
  int? get awaySeconds {
    final value = metadata?['away_ms'];
    if (value is num && value >= 0) return (value ~/ 1000).toInt();
    return null;
  }

  factory SecurityEvent.fromJson(Map<String, dynamic> json) => SecurityEvent(
        id: json['id'] as int,
        eventType: json['event_type'] as String,
        severity: json['severity'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

class AttemptSecurityReport {
  const AttemptSecurityReport({
    required this.attemptId,
    required this.studentName,
    required this.totalEvents,
    required this.warnings,
    required this.critical,
    required this.events,
  });

  final int attemptId;
  final String studentName;
  final int totalEvents;
  final int warnings;
  final int critical;
  final List<SecurityEvent> events;

  factory AttemptSecurityReport.fromJson(Map<String, dynamic> json) =>
      AttemptSecurityReport(
        attemptId: json['attempt_id'] as int,
        studentName: json['student_name'] as String,
        totalEvents: json['total_events'] as int? ?? 0,
        warnings: json['warnings'] as int? ?? 0,
        critical: json['critical'] as int? ?? 0,
        events: (json['events'] as List<dynamic>? ?? const [])
            .map((item) => SecurityEvent.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}
