enum AttemptStatus {
  active('active', 'In progress'),
  submitted('submitted', 'Submitted'),
  autoSubmitted('auto_submitted', 'Auto-submitted'),
  terminated('terminated', 'Terminated');

  const AttemptStatus(this.wire, this.label);

  final String wire;
  final String label;

  static AttemptStatus fromJson(String value) => AttemptStatus.values.firstWhere(
        (item) => item.wire == value,
        orElse: () => throw FormatException('Unknown attempt status: $value'),
      );
}

/// One option as the student sees it. There is no `isCorrect` field to leak.
class AttemptOption {
  const AttemptOption({required this.id, this.optionText, this.optionImageUrl});

  final int id;
  final String? optionText;
  final String? optionImageUrl;

  factory AttemptOption.fromJson(Map<String, dynamic> json) => AttemptOption(
        id: json['id'] as int,
        optionText: json['option_text'] as String?,
        optionImageUrl: json['option_image_url'] as String?,
      );
}

class AttemptQuestion {
  const AttemptQuestion({
    required this.examQuestionId,
    required this.position,
    required this.type,
    required this.questionText,
    required this.marks,
    required this.options,
    this.questionImageUrl,
    this.selectedOptionId,
    this.answerText,
    this.language,
    this.timeLimitSeconds,
    this.memoryLimitMb,
  });

  final int examQuestionId;

  /// 1-based position in this student's own paper, which may be shuffled.
  final int position;
  final String type;
  final String questionText;
  final int marks;
  final List<AttemptOption> options;
  final String? questionImageUrl;
  final int? selectedOptionId;
  final String? answerText;

  /// CODE_ANSWER only: shown beside the editor so the rules are visible.
  final String? language;
  final int? timeLimitSeconds;
  final int? memoryLimitMb;

  bool get isChoice => options.isNotEmpty;
  bool get isCode => type == 'CODE_ANSWER';
  bool get hasImageStem => questionImageUrl != null && questionImageUrl!.isNotEmpty;

  bool get isAnswered =>
      selectedOptionId != null || (answerText != null && answerText!.trim().isNotEmpty);

  AttemptQuestion copyWith({
    int? selectedOptionId,
    bool clearSelection = false,
    String? answerText,
    bool clearText = false,
  }) {
    return AttemptQuestion(
      examQuestionId: examQuestionId,
      position: position,
      type: type,
      questionText: questionText,
      marks: marks,
      options: options,
      questionImageUrl: questionImageUrl,
      selectedOptionId: clearSelection ? null : (selectedOptionId ?? this.selectedOptionId),
      answerText: clearText ? null : (answerText ?? this.answerText),
      language: language,
      timeLimitSeconds: timeLimitSeconds,
      memoryLimitMb: memoryLimitMb,
    );
  }

  factory AttemptQuestion.fromJson(Map<String, dynamic> json) => AttemptQuestion(
        examQuestionId: json['exam_question_id'] as int,
        position: json['position'] as int,
        type: json['type'] as String,
        questionText: json['question_text'] as String,
        marks: json['marks'] as int,
        questionImageUrl: json['question_image_url'] as String?,
        selectedOptionId: json['selected_option_id'] as int?,
        answerText: json['answer_text'] as String?,
        language: json['language'] as String?,
        timeLimitSeconds: json['time_limit_seconds'] as int?,
        memoryLimitMb: json['memory_limit_mb'] as int?,
        options: (json['options'] as List<dynamic>? ?? const [])
            .map((option) => AttemptOption.fromJson(option as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// An exam in progress, exactly as the server describes it.
class Attempt {
  const Attempt({
    required this.id,
    required this.examId,
    required this.examTitle,
    required this.courseCode,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.remainingSeconds,
    required this.durationMinutes,
    required this.totalMarks,
    required this.allowBackNavigation,
    required this.secureMode,
    required this.questions,
    required this.answeredCount,
    required this.totalQuestions,
    this.submittedAt,
  });

  final int id;
  final int examId;
  final String examTitle;
  final String courseCode;
  final AttemptStatus status;
  final DateTime startedAt;
  final DateTime expiresAt;

  /// The authoritative countdown. The on-screen timer is seeded from this and re-synced
  /// from it on every request; it is never computed from the device clock.
  final int remainingSeconds;
  final int durationMinutes;
  final int totalMarks;
  final bool allowBackNavigation;

  /// Whether this exam asks for device lockdown (§37).
  final bool secureMode;
  final List<AttemptQuestion> questions;
  final int answeredCount;
  final int totalQuestions;
  final DateTime? submittedAt;

  bool get isActive => status == AttemptStatus.active;
  int get unansweredCount => totalQuestions - answeredCount;

  Attempt copyWith({
    List<AttemptQuestion>? questions,
    int? answeredCount,
    int? remainingSeconds,
    AttemptStatus? status,
  }) {
    return Attempt(
      id: id,
      examId: examId,
      examTitle: examTitle,
      courseCode: courseCode,
      status: status ?? this.status,
      startedAt: startedAt,
      expiresAt: expiresAt,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      durationMinutes: durationMinutes,
      totalMarks: totalMarks,
      allowBackNavigation: allowBackNavigation,
      secureMode: secureMode,
      questions: questions ?? this.questions,
      answeredCount: answeredCount ?? this.answeredCount,
      totalQuestions: totalQuestions,
      submittedAt: submittedAt,
    );
  }

  factory Attempt.fromJson(Map<String, dynamic> json) => Attempt(
        id: json['id'] as int,
        examId: json['exam_id'] as int,
        examTitle: json['exam_title'] as String,
        courseCode: json['course_code'] as String,
        status: AttemptStatus.fromJson(json['status'] as String),
        startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
        expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String).toLocal(),
        remainingSeconds: json['remaining_seconds'] as int,
        durationMinutes: json['duration_minutes'] as int,
        totalMarks: json['total_marks'] as int,
        allowBackNavigation: json['allow_back_navigation'] as bool? ?? true,
        secureMode: json['secure_mode'] as bool? ?? true,
        answeredCount: json['answered_count'] as int,
        totalQuestions: json['total_questions'] as int,
        questions: (json['questions'] as List<dynamic>? ?? const [])
            .map((item) => AttemptQuestion.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// What the server reports back after a submission.
class SubmitOutcome {
  const SubmitOutcome({
    required this.attemptId,
    required this.status,
    required this.submittedAt,
    required this.answeredCount,
    required this.totalQuestions,
    this.resultId,
  });

  final int attemptId;
  final AttemptStatus status;
  final DateTime submittedAt;
  final int answeredCount;
  final int totalQuestions;

  /// Present only when the exam reveals results immediately.
  final int? resultId;

  factory SubmitOutcome.fromJson(Map<String, dynamic> json) => SubmitOutcome(
        attemptId: json['attempt_id'] as int,
        status: AttemptStatus.fromJson(json['status'] as String),
        submittedAt: DateTime.parse(json['submitted_at'] as String).toLocal(),
        answeredCount: json['answered_count'] as int,
        totalQuestions: json['total_questions'] as int,
        resultId: json['result_id'] as int?,
      );
}
