import 'package:uniexam/models/department.dart';

/// The three roles the backend recognises.
enum UserRole {
  admin,
  teacher,
  student;

  static UserRole fromJson(String value) => UserRole.values.firstWhere(
        (role) => role.name == value,
        // An unknown role must not silently become a privileged one.
        orElse: () => throw FormatException('Unknown role: $value'),
      );

  String get label => switch (this) {
        UserRole.admin => 'Administrator',
        UserRole.teacher => 'Teacher',
        UserRole.student => 'Student',
      };
}

/// The compact user object the API embeds in lists — an enrolment row, a login
/// response — where the full profile would be dead weight.
class UserSummary {
  const UserSummary({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
  });

  final int id;
  final String userId;
  final String name;
  final UserRole role;

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
        id: json['id'] as int,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        role: UserRole.fromJson(json['role'] as String),
      );
}

class StudentProfile {
  const StudentProfile({
    required this.studentId,
    this.departmentId,
    this.semester,
    this.session,
  });

  final String studentId;
  final int? departmentId;
  final int? semester;
  final String? session;

  factory StudentProfile.fromJson(Map<String, dynamic> json) => StudentProfile(
        studentId: json['student_id'] as String,
        departmentId: json['department_id'] as int?,
        semester: json['semester'] as int?,
        session: json['session'] as String?,
      );
}

class TeacherProfile {
  const TeacherProfile({
    required this.teacherId,
    this.departmentId,
    this.designation,
  });

  final String teacherId;
  final int? departmentId;
  final String? designation;

  factory TeacherProfile.fromJson(Map<String, dynamic> json) => TeacherProfile(
        teacherId: json['teacher_id'] as String,
        departmentId: json['department_id'] as int?,
        designation: json['designation'] as String?,
      );
}

class User {
  const User({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
    this.email,
    this.departmentId,
    this.department,
    this.isActive = true,
    this.studentProfile,
    this.teacherProfile,
  });

  final int id;
  final String userId;
  final String name;
  final UserRole role;
  final String? email;
  final int? departmentId;

  /// Present on the `/auth/me` payload, absent from the compact login object.
  final Department? department;
  final bool isActive;
  final StudentProfile? studentProfile;
  final TeacherProfile? teacherProfile;

  bool get isTeacher => role == UserRole.teacher;
  bool get isStudent => role == UserRole.student;
  bool get isAdmin => role == UserRole.admin;

  /// Handles both the compact `user` object inside a login response and the full
  /// `/auth/me` payload.
  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        role: UserRole.fromJson(json['role'] as String),
        email: json['email'] as String?,
        departmentId: json['department_id'] as int?,
        department: json['department'] == null
            ? null
            : Department.fromJson(json['department'] as Map<String, dynamic>),
        isActive: json['is_active'] as bool? ?? true,
        studentProfile: json['student_profile'] == null
            ? null
            : StudentProfile.fromJson(json['student_profile'] as Map<String, dynamic>),
        teacherProfile: json['teacher_profile'] == null
            ? null
            : TeacherProfile.fromJson(json['teacher_profile'] as Map<String, dynamic>),
      );
}
