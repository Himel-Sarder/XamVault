class Department {
  const Department({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  final int id;
  final String code;
  final String name;
  final bool isActive;

  factory Department.fromJson(Map<String, dynamic> json) => Department(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
      );
}

/// Who would be left without a department if this one were deleted.
///
/// Nothing is destroyed: every reference is SET NULL server-side, so a course or a
/// person simply becomes unassigned. Still worth saying before the fact, because
/// somebody has to put it right afterwards.
class DepartmentDeletionImpact {
  const DepartmentDeletionImpact({
    required this.courses,
    required this.teachers,
    required this.students,
  });

  final int courses;
  final int teachers;
  final int students;

  bool get isEmpty => courses == 0 && teachers == 0 && students == 0;

  /// "3 courses", "12 students" -- only the ones that are not zero.
  List<String> get affected => [
        if (courses > 0) '$courses ${courses == 1 ? 'course' : 'courses'}',
        if (teachers > 0) '$teachers ${teachers == 1 ? 'teacher' : 'teachers'}',
        if (students > 0) '$students ${students == 1 ? 'student' : 'students'}',
      ];

  factory DepartmentDeletionImpact.fromJson(Map<String, dynamic> json) =>
      DepartmentDeletionImpact(
        courses: json['courses'] as int? ?? 0,
        teachers: json['teachers'] as int? ?? 0,
        students: json['students'] as int? ?? 0,
      );
}
