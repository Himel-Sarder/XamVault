/// Where an exam sits relative to the server clock. Computed by the backend; the app
/// only renders it, so a device with a wrong clock shows the same thing as everyone else.
enum ExamAvailability {
  upcoming('upcoming', 'Upcoming'),
  open('open', 'Open now'),
  closed('closed', 'Ended');

  const ExamAvailability(this.wire, this.label);

  final String wire;
  final String label;

  static ExamAvailability fromJson(String value) =>
      ExamAvailability.values.firstWhere(
        (item) => item.wire == value,
        orElse: () => throw FormatException('Unknown availability: $value'),
      );
}

enum JoinRequestStatus {
  none('none', 'Not requested'),
  pending('pending', 'Awaiting approval'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Not approved');

  const JoinRequestStatus(this.wire, this.label);

  final String wire;
  final String label;

  static JoinRequestStatus fromJson(String value) =>
      JoinRequestStatus.values.firstWhere(
        (item) => item.wire == value,
        orElse: () => throw FormatException('Unknown join request status: $value'),
      );
}

/// The settings a student is told about before starting.
class StudentExamSettings {
  const StudentExamSettings({
    required this.secureMode,
    required this.allowBackNavigation,
    required this.maxAttempts,
  });

  final bool secureMode;
  final bool allowBackNavigation;
  final int maxAttempts;

  factory StudentExamSettings.fromJson(Map<String, dynamic> json) => StudentExamSettings(
        secureMode: json['secure_mode'] as bool,
        allowBackNavigation: json['allow_back_navigation'] as bool,
        maxAttempts: json['max_attempts'] as int,
      );
}

/// A published exam as a student sees it.
///
/// Deliberately not the teacher's [Exam] with fields blanked out: this class simply has
/// no `teacher_id`, no draft state and no answer key, so none can leak.
class StudentExam {
  const StudentExam({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.title,
    required this.durationMinutes,
    required this.totalMarks,
    required this.questionCount,
    required this.availability,
    required this.joinRequestStatus,
    required this.canRequestJoin,
    this.admitsAnyoneEnrolled = false,
    required this.settings,
    this.description,
    this.startAt,
    this.expiresAt,
  });

  final int id;
  final int courseId;
  final String courseCode;
  final String courseName;
  final String title;
  final String? description;
  final DateTime? startAt;
  final int durationMinutes;
  final DateTime? expiresAt;
  final int totalMarks;
  final int questionCount;
  final ExamAvailability availability;
  final JoinRequestStatus joinRequestStatus;
  final bool canRequestJoin;

  /// This exam lets anyone enrolled sit it, so there is no request to make.
  final bool admitsAnyoneEnrolled;
  final StudentExamSettings settings;

  /// Whether this student may start: approved by hand, or admitted by the exam
  /// admitting everyone enrolled.
  ///
  /// The server decides the same thing independently -- this only chooses which button
  /// to draw. An exam that admits everyone still refuses a student it rejected, and
  /// the server sends `admits_anyone_enrolled: false` for them.
  bool get isApproved =>
      admitsAnyoneEnrolled || joinRequestStatus == JoinRequestStatus.approved;
  bool get isPending => joinRequestStatus == JoinRequestStatus.pending;

  factory StudentExam.fromJson(Map<String, dynamic> json) => StudentExam(
        id: json['id'] as int,
        courseId: json['course_id'] as int,
        courseCode: json['course_code'] as String,
        courseName: json['course_name'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        startAt: json['start_at'] == null
            ? null
            : DateTime.parse(json['start_at'] as String).toLocal(),
        durationMinutes: json['duration_minutes'] as int,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String).toLocal(),
        totalMarks: json['total_marks'] as int,
        questionCount: json['question_count'] as int,
        availability: ExamAvailability.fromJson(json['availability'] as String),
        joinRequestStatus: JoinRequestStatus.fromJson(json['join_request_status'] as String),
        canRequestJoin: json['can_request_join'] as bool,
        admitsAnyoneEnrolled: json['admits_anyone_enrolled'] as bool? ?? false,
        settings: StudentExamSettings.fromJson(json['settings'] as Map<String, dynamic>),
      );
}
