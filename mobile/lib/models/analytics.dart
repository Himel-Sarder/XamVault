class CohortCounts {
  const CohortCounts({
    required this.approved,
    required this.submitted,
    required this.inProgress,
    required this.absent,
  });

  final int approved;
  final int submitted;
  final int inProgress;
  final int absent;

  factory CohortCounts.fromJson(Map<String, dynamic> json) => CohortCounts(
        approved: json['approved'] as int,
        submitted: json['submitted'] as int,
        inProgress: json['in_progress'] as int,
        absent: json['absent'] as int,
      );
}

/// All null when nobody has sat the exam — an average of nothing is not zero.
class ScoreSummary {
  const ScoreSummary({this.average, this.highest, this.lowest, this.median});

  final double? average;
  final double? highest;
  final double? lowest;
  final double? median;

  bool get hasData => average != null;

  factory ScoreSummary.fromJson(Map<String, dynamic> json) => ScoreSummary(
        average: (json['average'] as num?)?.toDouble(),
        highest: (json['highest'] as num?)?.toDouble(),
        lowest: (json['lowest'] as num?)?.toDouble(),
        median: (json['median'] as num?)?.toDouble(),
      );
}

class DistributionBucket {
  const DistributionBucket({required this.label, required this.count});

  final String label;
  final int count;

  factory DistributionBucket.fromJson(Map<String, dynamic> json) => DistributionBucket(
        label: json['label'] as String,
        count: json['count'] as int,
      );
}

class QuestionAnalytics {
  const QuestionAnalytics({
    required this.examQuestionId,
    required this.position,
    required this.type,
    required this.questionText,
    required this.marks,
    required this.isAutoMarked,
    required this.answered,
    required this.skipped,
    required this.awaitingMarks,
    this.correct,
    this.wrong,
    this.correctRate,
    this.averageMarks,
  });

  final int examQuestionId;
  final int position;
  final String type;
  final String questionText;
  final int marks;

  /// Choice questions have an accuracy; written ones have an average mark instead.
  final bool isAutoMarked;
  final int answered;
  final int skipped;
  final int awaitingMarks;
  final int? correct;
  final int? wrong;
  final double? correctRate;
  final double? averageMarks;

  factory QuestionAnalytics.fromJson(Map<String, dynamic> json) => QuestionAnalytics(
        examQuestionId: json['exam_question_id'] as int,
        position: json['position'] as int,
        type: json['type'] as String,
        questionText: json['question_text'] as String,
        marks: json['marks'] as int,
        isAutoMarked: json['is_auto_marked'] as bool,
        answered: json['answered'] as int,
        skipped: json['skipped'] as int,
        awaitingMarks: json['awaiting_marks'] as int? ?? 0,
        correct: json['correct'] as int?,
        wrong: json['wrong'] as int?,
        correctRate: (json['correct_rate'] as num?)?.toDouble(),
        averageMarks: (json['average_marks'] as num?)?.toDouble(),
      );
}

class ExamAnalytics {
  const ExamAnalytics({
    required this.examId,
    required this.examTitle,
    required this.courseCode,
    required this.totalMarks,
    required this.cohort,
    required this.scores,
    required this.passPercentage,
    required this.passed,
    required this.failed,
    required this.distribution,
    required this.questions,
    this.passRate,
  });

  final int examId;
  final String examTitle;
  final String courseCode;
  final int totalMarks;
  final CohortCounts cohort;
  final ScoreSummary scores;

  /// The threshold these counts were computed at — supplied, not assumed.
  final double passPercentage;
  final int passed;
  final int failed;
  final double? passRate;
  final List<DistributionBucket> distribution;
  final List<QuestionAnalytics> questions;

  factory ExamAnalytics.fromJson(Map<String, dynamic> json) => ExamAnalytics(
        examId: json['exam_id'] as int,
        examTitle: json['exam_title'] as String,
        courseCode: json['course_code'] as String,
        totalMarks: json['total_marks'] as int,
        cohort: CohortCounts.fromJson(json['cohort'] as Map<String, dynamic>),
        scores: ScoreSummary.fromJson(json['scores'] as Map<String, dynamic>),
        passPercentage: (json['pass_percentage'] as num).toDouble(),
        passed: json['passed'] as int,
        failed: json['failed'] as int,
        passRate: (json['pass_rate'] as num?)?.toDouble(),
        distribution: (json['distribution'] as List<dynamic>? ?? const [])
            .map((item) => DistributionBucket.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        questions: (json['questions'] as List<dynamic>? ?? const [])
            .map((item) => QuestionAnalytics.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}
