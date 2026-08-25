import 'package:uniexam/models/question.dart';

/// A reusable question from the teacher's library, with how widely it is already used.
class BankQuestion {
  const BankQuestion({
    required this.id,
    required this.type,
    required this.questionText,
    required this.marks,
    required this.options,
    required this.usedInExams,
    required this.usedInPublished,
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

  /// How many exams link to this question.
  final int usedInExams;

  /// True if any of them is published. Editing is still safe — a published exam renders
  /// from its own frozen snapshot — but the teacher should know it is in circulation.
  final bool usedInPublished;

  final String? questionImageUrl;
  final String? difficulty;
  final String? topic;
  final String? language;
  final int? timeLimitSeconds;
  final int? memoryLimitMb;

  bool get isDeletable => usedInExams == 0;

  /// The same shape the question builder edits, so one screen serves both.
  Question toQuestion() => Question(
        id: id,
        type: type,
        questionText: questionText,
        marks: marks,
        options: options,
        questionImageUrl: questionImageUrl,
        difficulty: difficulty,
        topic: topic,
        language: language,
        timeLimitSeconds: timeLimitSeconds,
        memoryLimitMb: memoryLimitMb,
      );

  factory BankQuestion.fromJson(Map<String, dynamic> json) => BankQuestion(
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
        usedInExams: json['used_in_exams'] as int? ?? 0,
        usedInPublished: json['used_in_published'] as bool? ?? false,
        options: (json['options'] as List<dynamic>? ?? const [])
            .map((option) => QuestionOption.fromJson(option as Map<String, dynamic>))
            .toList(growable: false),
      );
}
