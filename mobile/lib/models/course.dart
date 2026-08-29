class Course {
  const Course({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.createdBy,
    this.teacherName,
    this.departmentId,
    this.studyYear,
    this.semester,
    this.session,
    this.isActive = true,
  });

  final int id;
  final String courseCode;
  final String courseName;
  final int createdBy;

  /// Who runs it. Present so an admin sees the holder without resolving an id.
  final String? teacherName;
  final int? departmentId;
  /// Year of the programme, 1 to 4. Named studyYear because `session` beside it
  /// already holds the academic year as "2025-2026".
  final int? studyYear;

  /// Which half of that year, 1 or 2.
  final int? semester;
  final String? session;
  final bool isActive;

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as int,
        courseCode: json['course_code'] as String,
        courseName: json['course_name'] as String,
        createdBy: json['created_by'] as int,
        teacherName: json['teacher_name'] as String?,
        departmentId: json['department_id'] as int?,
        studyYear: json['study_year'] as int?,
        semester: json['semester'] as int?,
        session: json['session'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );
}
