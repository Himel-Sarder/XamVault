/// The question types the platform will support. Only [textMcq] is implemented today;
/// the rest arrive in later phases and the backend already stores them.
enum QuestionType {
  textMcq('TEXT_MCQ', 'Multiple choice'),
  imageTextOptions('IMAGE_TEXT_OPTIONS', 'Image with text options'),
  imageImageOptions('IMAGE_IMAGE_OPTIONS', 'Image with image options'),
  shortAnswer('SHORT_ANSWER', 'Short answer'),
  codeAnswer('CODE_ANSWER', 'Code');

  const QuestionType(this.wire, this.label);

  final String wire;
  final String label;

  static QuestionType fromJson(String value) => QuestionType.values.firstWhere(
        (type) => type.wire == value,
        orElse: () => throw FormatException('Unknown question type: $value'),
      );
}

class QuestionOption {
  const QuestionOption({
    required this.id,
    required this.displayOrder,
    required this.isCorrect,
    this.optionText,
    this.optionImageUrl,
  });

  final int id;
  final int displayOrder;

  /// Teacher-facing only. No student response schema declares this field.
  final bool isCorrect;
  final String? optionText;
  final String? optionImageUrl;

  factory QuestionOption.fromJson(Map<String, dynamic> json) => QuestionOption(
        id: json['id'] as int,
        displayOrder: json['display_order'] as int,
        isCorrect: json['is_correct'] as bool? ?? false,
        optionText: json['option_text'] as String?,
        optionImageUrl: json['option_image_url'] as String?,
      );
}

class Question {
  const Question({
    required this.id,
    required this.type,
    required this.questionText,
    required this.marks,
    required this.options,
    this.questionImageUrl,
    this.difficulty,
    this.topic,
    this.language,
    this.timeLimitSeconds,
    this.memoryLimitMb,
  });

  final int id;
  final QuestionType type;
  final String questionText;
  final int marks;
  final List<QuestionOption> options;
  final String? questionImageUrl;
  final String? difficulty;
  final String? topic;

  /// CODE_ANSWER only.
  final String? language;
  final int? timeLimitSeconds;
  final int? memoryLimitMb;

  bool get isChoice => const {
        QuestionType.textMcq,
        QuestionType.imageTextOptions,
        QuestionType.imageImageOptions,
      }.contains(type);

  bool get isManuallyGraded => !isChoice;
  bool get hasImageStem => questionImageUrl != null && questionImageUrl!.isNotEmpty;

  QuestionOption? get correctOption {
    for (final option in options) {
      if (option.isCorrect) return option;
    }
    return null;
  }

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as int,
        type: QuestionType.fromJson(json['type'] as String),
        questionText: json['question_text'] as String,
        marks: json['marks'] as int,
        questionImageUrl: json['question_image_url'] as String?,
        difficulty: json['difficulty'] as String?,
        topic: json['topic'] as String?,
        language: json['language'] as String?,
        timeLimitSeconds: json['time_limit_seconds'] as int?,
        memoryLimitMb: json['memory_limit_mb'] as int?,
        options: (json['options'] as List<dynamic>? ?? const [])
            .map((option) => QuestionOption.fromJson(option as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// A question as it sits inside one exam.
class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.examId,
    required this.displayOrder,
    required this.marks,
    required this.isFrozen,
    required this.question,
  });

  final int id;
  final int examId;
  final int displayOrder;
  final int marks;

  /// True once the exam is published and this question is served from its snapshot.
  final bool isFrozen;
  final Question question;

  factory ExamQuestion.fromJson(Map<String, dynamic> json) => ExamQuestion(
        id: json['id'] as int,
        examId: json['exam_id'] as int,
        displayOrder: json['display_order'] as int,
        marks: json['marks_snapshot'] as int,
        isFrozen: json['is_frozen'] as bool? ?? false,
        question: Question.fromJson(json['question'] as Map<String, dynamic>),
      );
}
