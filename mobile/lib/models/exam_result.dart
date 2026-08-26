class ScoreBreakdown {
  const ScoreBreakdown({required this.mcq, required this.shortAnswer, required this.code});

  final double mcq;
  final double shortAnswer;
  final double code;

  factory ScoreBreakdown.fromJson(Map<String, dynamic> json) => ScoreBreakdown(
        mcq: (json['mcq'] as num).toDouble(),
        shortAnswer: (json['short_answer'] as num).toDouble(),
        code: (json['code'] as num).toDouble(),
      );
}

/// A student's own result. The API only ever returns published ones.
class ExamResult {
  const ExamResult({
    required this.id,
    required this.examId,
    required this.examTitle,
    required this.courseCode,
    required this.attemptId,
    required this.scores,
    required this.totalScore,
    required this.totalMarks,
    required this.percentage,
    required this.status,
    this.submittedAt,
    this.publishedAt,
  });

  final int id;
  final int examId;
  final String examTitle;
  final String courseCode;
  final int attemptId;
  final ScoreBreakdown scores;
  final double totalScore;
  final int totalMarks;
  final double percentage;
  final String status;
  final DateTime? submittedAt;
  final DateTime? publishedAt;

  factory ExamResult.fromJson(Map<String, dynamic> json) => ExamResult(
        id: json['id'] as int,
        examId: json['exam_id'] as int,
        examTitle: json['exam_title'] as String,
        courseCode: json['course_code'] as String,
        attemptId: json['attempt_id'] as int,
        scores: ScoreBreakdown.fromJson(json['scores'] as Map<String, dynamic>),
        totalScore: (json['total_score'] as num).toDouble(),
        totalMarks: json['total_marks'] as int,
        percentage: (json['percentage'] as num).toDouble(),
        status: json['status'] as String,
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String).toLocal(),
        publishedAt: json['published_at'] == null
            ? null
            : DateTime.parse(json['published_at'] as String).toLocal(),
      );
}

/// The same result seen by the teacher who owns the exam.
class TeacherResult {
  const TeacherResult({
    required this.id,
    required this.examId,
    required this.attemptId,
    required this.studentName,
    required this.studentNumber,
    required this.scores,
    required this.totalScore,
    required this.totalMarks,
    required this.percentage,
    required this.status,
    this.submittedAt,
    this.publishedAt,
  });

  final int id;
  final int examId;
  final int attemptId;
  final String studentName;
  final String studentNumber;
  final ScoreBreakdown scores;
  final double totalScore;
  final int totalMarks;
  final double percentage;
  final String status;
  final DateTime? submittedAt;
  final DateTime? publishedAt;

  bool get isPublished => status == 'published';

  factory TeacherResult.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>;
    return TeacherResult(
      id: json['id'] as int,
      examId: json['exam_id'] as int,
      attemptId: json['attempt_id'] as int,
      studentName: student['name'] as String,
      studentNumber: (student['student_number'] ?? student['user_id']) as String,
      scores: ScoreBreakdown.fromJson(json['scores'] as Map<String, dynamic>),
      totalScore: (json['total_score'] as num).toDouble(),
      totalMarks: json['total_marks'] as int,
      percentage: (json['percentage'] as num).toDouble(),
      status: json['status'] as String,
      submittedAt: json['submitted_at'] == null
          ? null
          : DateTime.parse(json['submitted_at'] as String).toLocal(),
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.parse(json['published_at'] as String).toLocal(),
    );
  }
}


/// One submitted attempt, and how much marking it still needs.
class GradingQueueEntry {
  const GradingQueueEntry({
    required this.attemptId,
    required this.studentName,
    required this.studentNumber,
    required this.awaitingMarks,
    required this.totalScore,
    required this.totalMarks,
    this.submittedAt,
  });

  final int attemptId;
  final String studentName;
  final String studentNumber;
  final int awaitingMarks;
  final double totalScore;
  final int totalMarks;
  final DateTime? submittedAt;

  bool get isFullyMarked => awaitingMarks == 0;

  factory GradingQueueEntry.fromJson(Map<String, dynamic> json) => GradingQueueEntry(
        attemptId: json['attempt_id'] as int,
        studentName: json['student_name'] as String,
        studentNumber: json['student_number'] as String,
        awaitingMarks: json['awaiting_marks'] as int,
        totalScore: (json['total_score'] as num).toDouble(),
        totalMarks: json['total_marks'] as int,
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String).toLocal(),
      );
}

/// A written answer beside the question it answers.
class AnswerToMark {
  const AnswerToMark({
    required this.answerId,
    required this.examQuestionId,
    required this.position,
    required this.type,
    required this.questionText,
    required this.maxMarks,
    required this.status,
    this.language,
    this.answerText,
    this.marksAwarded,
    this.feedback,
  });

  final int? answerId;
  final int examQuestionId;
  final int position;
  final String type;
  final String questionText;
  final int maxMarks;
  final String status;
  final String? language;
  final String? answerText;
  final double? marksAwarded;
  final String? feedback;

  bool get isCode => type == 'CODE_ANSWER';
  bool get isMarked => status == 'evaluated';
  bool get wasAnswered => answerText != null && answerText!.trim().isNotEmpty;

  factory AnswerToMark.fromJson(Map<String, dynamic> json) => AnswerToMark(
        answerId: json['answer_id'] as int?,
        examQuestionId: json['exam_question_id'] as int,
        position: json['position'] as int,
        type: json['type'] as String,
        questionText: json['question_text'] as String,
        maxMarks: json['max_marks'] as int,
        status: json['status'] as String,
        language: json['language'] as String?,
        answerText: json['answer_text'] as String?,
        marksAwarded: (json['marks_awarded'] as num?)?.toDouble(),
        feedback: json['feedback'] as String?,
      );
}

class AttemptGrading {
  const AttemptGrading({
    required this.attemptId,
    required this.examTitle,
    required this.studentName,
    required this.awaitingMarks,
    required this.answers,
    this.submittedAt,
  });

  final int attemptId;
  final String examTitle;
  final String studentName;
  final int awaitingMarks;
  final List<AnswerToMark> answers;
  final DateTime? submittedAt;

  factory AttemptGrading.fromJson(Map<String, dynamic> json) => AttemptGrading(
        attemptId: json['attempt_id'] as int,
        examTitle: json['exam_title'] as String,
        studentName: json['student_name'] as String,
        awaitingMarks: json['awaiting_marks'] as int,
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String).toLocal(),
        answers: (json['answers'] as List<dynamic>? ?? const [])
            .map((item) => AnswerToMark.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}
