import 'package:uniexam/models/student_exam.dart';

/// Who asked. Enough for a teacher to recognise the student, nothing more.
class JoinRequestStudent {
  const JoinRequestStudent({
    required this.id,
    required this.userId,
    required this.name,
    this.studentNumber,
  });

  final int id;
  final String userId;
  final String name;
  final String? studentNumber;

  factory JoinRequestStudent.fromJson(Map<String, dynamic> json) => JoinRequestStudent(
        id: json['id'] as int,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        studentNumber: json['student_number'] as String?,
      );
}

/// Teacher-facing view of one request.
class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.examId,
    required this.status,
    required this.requestedAt,
    required this.student,
    this.reviewedAt,
    this.reviewedBy,
  });

  final int id;
  final int examId;
  final JoinRequestStatus status;
  final DateTime requestedAt;
  final JoinRequestStudent student;
  final DateTime? reviewedAt;
  final int? reviewedBy;

  bool get isPending => status == JoinRequestStatus.pending;

  factory JoinRequest.fromJson(Map<String, dynamic> json) => JoinRequest(
        id: json['id'] as int,
        examId: json['exam_id'] as int,
        status: JoinRequestStatus.fromJson(json['status'] as String),
        requestedAt: DateTime.parse(json['requested_at'] as String).toLocal(),
        reviewedAt: json['reviewed_at'] == null
            ? null
            : DateTime.parse(json['reviewed_at'] as String).toLocal(),
        reviewedBy: json['reviewed_by'] as int?,
        student: JoinRequestStudent.fromJson(json['student'] as Map<String, dynamic>),
      );
}

/// The student's own request, with enough context to read in a list.
class MyJoinRequest {
  const MyJoinRequest({
    required this.id,
    required this.examId,
    required this.examTitle,
    required this.courseCode,
    required this.status,
    required this.requestedAt,
    this.reviewedAt,
  });

  final int id;
  final int examId;
  final String examTitle;
  final String courseCode;
  final JoinRequestStatus status;
  final DateTime requestedAt;
  final DateTime? reviewedAt;

  factory MyJoinRequest.fromJson(Map<String, dynamic> json) => MyJoinRequest(
        id: json['id'] as int,
        examId: json['exam_id'] as int,
        examTitle: json['exam_title'] as String,
        courseCode: json['course_code'] as String,
        status: JoinRequestStatus.fromJson(json['status'] as String),
        requestedAt: DateTime.parse(json['requested_at'] as String).toLocal(),
        reviewedAt: json['reviewed_at'] == null
            ? null
            : DateTime.parse(json['reviewed_at'] as String).toLocal(),
      );
}
