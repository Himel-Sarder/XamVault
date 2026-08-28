class Course {
  const Course({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.createdBy,
    this.teacherName,
    this.departmentId,
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
        semester: json['semester'] as int?,
        session: json['session'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );
}
