enum ExamStatus {
  draft('draft', 'Draft'),
  published('published', 'Published'),
  running('running', 'Running'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const ExamStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ExamStatus fromJson(String value) => ExamStatus.values.firstWhere(
        (status) => status.wire == value,
        orElse: () => throw FormatException('Unknown exam status: $value'),
      );
}

class ExamSettings {
  const ExamSettings({
    this.shuffleQuestions = false,
    this.shuffleAnswers = false,
    this.allowBackNavigation = true,
    this.autoSubmit = true,
    this.secureMode = true,
    this.showResultImmediately = false,
    this.maxAttempts = 1,
  });

  final bool shuffleQuestions;
  final bool shuffleAnswers;
  final bool allowBackNavigation;
  final bool autoSubmit;
  final bool secureMode;
  final bool showResultImmediately;
  final int maxAttempts;

  factory ExamSettings.fromJson(Map<String, dynamic> json) => ExamSettings(
        shuffleQuestions: json['shuffle_questions'] as bool? ?? false,
        shuffleAnswers: json['shuffle_answers'] as bool? ?? false,
        allowBackNavigation: json['allow_back_navigation'] as bool? ?? true,
        autoSubmit: json['auto_submit'] as bool? ?? true,
        secureMode: json['secure_mode'] as bool? ?? true,
        showResultImmediately: json['show_result_immediately'] as bool? ?? false,
        maxAttempts: json['max_attempts'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'shuffle_questions': shuffleQuestions,
        'shuffle_answers': shuffleAnswers,
        'allow_back_navigation': allowBackNavigation,
        'auto_submit': autoSubmit,
        'secure_mode': secureMode,
        'show_result_immediately': showResultImmediately,
        'max_attempts': maxAttempts,
      };

  ExamSettings copyWith({
    bool? shuffleQuestions,
    bool? shuffleAnswers,
    bool? allowBackNavigation,
    bool? autoSubmit,
    bool? secureMode,
    bool? showResultImmediately,
    int? maxAttempts,
  }) =>
      ExamSettings(
        shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
        shuffleAnswers: shuffleAnswers ?? this.shuffleAnswers,
        allowBackNavigation: allowBackNavigation ?? this.allowBackNavigation,
        autoSubmit: autoSubmit ?? this.autoSubmit,
        secureMode: secureMode ?? this.secureMode,
        showResultImmediately: showResultImmediately ?? this.showResultImmediately,
        maxAttempts: maxAttempts ?? this.maxAttempts,
      );
}

class Exam {
  const Exam({
    required this.id,
    required this.courseId,
    required this.teacherId,
    required this.title,
    required this.durationMinutes,
    required this.totalMarks,
    required this.status,
    required this.questionCount,
    this.description,
    this.startAt,
    this.expiresAt,
    this.publishedAt,
    this.settings,
  });

  final int id;
  final int courseId;
  final int teacherId;
  final String title;
  final String? description;

  /// All times are UTC from the server; the UI converts to local for display only.
  final DateTime? startAt;
  final int durationMinutes;

  /// Derived server-side at publish (start + duration). Never sent by the client.
  final DateTime? expiresAt;
  final int totalMarks;
  final ExamStatus status;
  final int questionCount;
  final DateTime? publishedAt;
  final ExamSettings? settings;

  bool get isDraft => status == ExamStatus.draft;
  bool get isEditable => status == ExamStatus.draft;

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
        id: json['id'] as int,
        courseId: json['course_id'] as int,
        teacherId: json['teacher_id'] as int,
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
        status: ExamStatus.fromJson(json['status'] as String),
        questionCount: json['question_count'] as int? ?? 0,
        publishedAt: json['published_at'] == null
            ? null
            : DateTime.parse(json['published_at'] as String).toLocal(),
        settings: json['settings'] == null
            ? null
            : ExamSettings.fromJson(json['settings'] as Map<String, dynamic>),
      );
}

/// One reason an exam cannot be published yet.
class PublishIssue {
  const PublishIssue({required this.field, required this.message});

  final String field;
  final String message;

  factory PublishIssue.fromJson(Map<String, dynamic> json) => PublishIssue(
        field: json['field'] as String,
        message: json['message'] as String,
      );
}

class PublishCheck {
  const PublishCheck({required this.canPublish, required this.issues});

  final bool canPublish;
  final List<PublishIssue> issues;

  factory PublishCheck.fromJson(Map<String, dynamic> json) => PublishCheck(
        canPublish: json['can_publish'] as bool,
        issues: (json['issues'] as List<dynamic>? ?? const [])
            .map((issue) => PublishIssue.fromJson(issue as Map<String, dynamic>))
            .toList(growable: false),
      );
}
