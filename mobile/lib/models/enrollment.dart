import 'package:uniexam/models/user.dart';

/// One student's place on a course.
class Enrollment {
  const Enrollment({
    required this.id,
    required this.courseId,
    required this.studentId,
    this.student,
  });

  final int id;
  final int courseId;
  final int studentId;

  /// The API embeds a compact student summary; it is absent only if the server
  /// could not load it, in which case the row still lists by id.
  final UserSummary? student;

  factory Enrollment.fromJson(Map<String, dynamic> json) => Enrollment(
        id: json['id'] as int,
        courseId: json['course_id'] as int,
        studentId: json['student_id'] as int,
        student: json['student'] == null
            ? null
            : UserSummary.fromJson(json['student'] as Map<String, dynamic>),
      );
}

/// Why one id in a pasted roll list produced no enrolment.
enum SkipReason {
  notFound,
  notAStudent,
  deactivated,
  alreadyEnrolled,

  /// A reason this build does not know about. Reporting it as "could not be enrolled"
  /// is honest; inventing a specific cause would not be.
  unknown;

  static SkipReason fromJson(String value) => switch (value) {
        'not_found' => SkipReason.notFound,
        'not_a_student' => SkipReason.notAStudent,
        'deactivated' => SkipReason.deactivated,
        'already_enrolled' => SkipReason.alreadyEnrolled,
        _ => SkipReason.unknown,
      };

  String get label => switch (this) {
        SkipReason.notFound => 'No student with that ID',
        SkipReason.notAStudent => 'Not a student account',
        SkipReason.deactivated => 'Account is deactivated',
        SkipReason.alreadyEnrolled => 'Already enrolled',
        SkipReason.unknown => 'Could not be enrolled',
      };
}

class SkippedEnrolment {
  const SkippedEnrolment({required this.studentUserId, required this.reason});

  final String studentUserId;
  final SkipReason reason;

  factory SkippedEnrolment.fromJson(Map<String, dynamic> json) => SkippedEnrolment(
        studentUserId: json['student_user_id'] as String,
        reason: SkipReason.fromJson(json['reason'] as String),
      );
}

/// What a bulk enrolment actually did, name by name.
class BulkEnrolmentResult {
  const BulkEnrolmentResult({required this.enrolled, required this.skipped});

  final List<UserSummary> enrolled;
  final List<SkippedEnrolment> skipped;

  int get enrolledCount => enrolled.length;
  int get skippedCount => skipped.length;

  factory BulkEnrolmentResult.fromJson(Map<String, dynamic> json) => BulkEnrolmentResult(
        enrolled: (json['enrolled'] as List<dynamic>? ?? const [])
            .map((item) => UserSummary.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        skipped: (json['skipped'] as List<dynamic>? ?? const [])
            .map((item) => SkippedEnrolment.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}
