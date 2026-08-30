import 'package:uniexam/models/study_stage.dart';

/// A student who could be put on a course's roll.
class EnrolmentCandidate {
  const EnrolmentCandidate({
    required this.id,
    required this.userId,
    required this.name,
    this.studentId,
    this.studyYear,
    this.semester,
    this.session,
  });

  final int id;
  final String userId;
  final String name;
  final String? studentId;
  final int? studyYear;
  final int? semester;
  final String? session;

  /// "3rd Year, 2nd Semester", or as much of it as is on record.
  String? get stage => studyStage(year: studyYear, semester: semester);

  factory EnrolmentCandidate.fromJson(Map<String, dynamic> json) => EnrolmentCandidate(
        id: json['id'] as int,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        studentId: json['student_id'] as String?,
        studyYear: json['study_year'] as int?,
        semester: json['semester'] as int?,
        session: json['session'] as String?,
      );
}

/// Who matched, and whether the list was cut short.
class EnrolmentCandidates {
  const EnrolmentCandidates({required this.items, required this.truncated});

  final List<EnrolmentCandidate> items;

  /// True when this is a page rather than the whole cohort. "Add all" must say so
  /// instead of quietly enrolling a different set from the one on screen.
  final bool truncated;

  factory EnrolmentCandidates.fromJson(Map<String, dynamic> json) => EnrolmentCandidates(
        items: (json['items'] as List<dynamic>)
            .map((item) => EnrolmentCandidate.fromJson(item as Map<String, dynamic>))
            .toList(),
        truncated: json['truncated'] as bool? ?? false,
      );
}
