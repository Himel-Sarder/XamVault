/// What deleting a course would take with it.
///
/// Read before the confirmation is shown rather than after the fact. A course is the
/// root of a fair amount — every exam written on it, and every attempt and result from
/// those exams — and none of that should be a surprise.
class CourseDeletionImpact {
  const CourseDeletionImpact({
    required this.exams,
    required this.questionsOnThoseExams,
    required this.attempts,
    required this.results,
    required this.enrolments,
  });

  final int exams;
  final int questionsOnThoseExams;
  final int attempts;
  final int results;
  final int enrolments;

  factory CourseDeletionImpact.fromJson(Map<String, dynamic> json) =>
      CourseDeletionImpact(
        exams: json['exams'] as int? ?? 0,
        questionsOnThoseExams: json['questions_on_those_exams'] as int? ?? 0,
        attempts: json['attempts'] as int? ?? 0,
        results: json['results'] as int? ?? 0,
        enrolments: json['enrolments'] as int? ?? 0,
      );

  /// Nothing but the course row itself would go.
  bool get isEmpty =>
      exams == 0 && attempts == 0 && results == 0 && enrolments == 0;

  /// The losses worth naming, longest-lived first, as "3 exams", "12 attempts".
  List<String> get losses => [
        if (exams > 0) '$exams ${exams == 1 ? 'exam' : 'exams'}',
        if (attempts > 0) '$attempts ${attempts == 1 ? 'attempt' : 'attempts'}',
        if (results > 0) '$results ${results == 1 ? 'result' : 'results'}',
        if (enrolments > 0)
          '$enrolments ${enrolments == 1 ? 'enrolment' : 'enrolments'}',
      ];
}
