import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/enrollment.dart';
import 'package:uniexam/models/paged.dart';

/// Courses and their rolls.
///
/// The backend already scopes every read by role, so there is nothing to filter here —
/// and nothing the client could widen. Ownership is likewise enforced server-side; the
/// screens hide what a caller cannot do, but hiding is not the control.
class CourseRepository {
  const CourseRepository(this._api);

  final ApiClient _api;

  Future<Paged<Course>> list({int page = 1, int pageSize = 20, bool activeOnly = false}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/courses',
      query: {'page': page, 'page_size': pageSize, 'active_only': activeOnly},
    );
    return Paged.fromJson(data, Course.fromJson);
  }

  Future<Course> get(int id) async {
    final data = await _api.get<Map<String, dynamic>>('/courses/$id');
    return Course.fromJson(data);
  }

  Future<Course> create({
    required String courseCode,
    required String courseName,
    int? departmentId,
    int? semester,
    String? session,
  }) async {
    final data = await _api.post<Map<String, dynamic>>('/courses', data: {
      'course_code': courseCode,
      'course_name': courseName,
      'department_id': ?departmentId,
      'semester': ?semester,
      'session': ?session,
    });
    return Course.fromJson(data);
  }

  /// Only the fields present are sent, so an untouched field is never overwritten.
  Future<Course> update(
    int id, {
    String? courseName,
    int? departmentId,
    int? semester,
    String? session,
    bool? isActive,
  }) async {
    final data = await _api.patch<Map<String, dynamic>>('/courses/$id', data: {
      'course_name': ?courseName,
      'department_id': ?departmentId,
      'semester': ?semester,
      'session': ?session,
      'is_active': ?isActive,
    });
    return Course.fromJson(data);
  }

  /// Puts a teacher in charge of a course. Administrators only.
  ///
  /// Returns how many exams stayed with the previous holder — reassigning does not
  /// rewrite authorship of work already done, and the new teacher would otherwise
  /// discover that by failing to open a paper.
  Future<({Course course, int examsKept})> assignTeacher(
    int courseId,
    String teacherUserId,
  ) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/courses/$courseId/assign',
      data: {'teacher_user_id': teacherUserId},
    );
    return (
      course: Course.fromJson(data['course'] as Map<String, dynamic>),
      examsKept: data['exams_kept_by_previous_teacher'] as int? ?? 0,
    );
  }

  // ------------------------------------------------------------- enrolment

  Future<List<Enrollment>> enrollments(int courseId) async {
    final data = await _api.get<List<dynamic>>('/courses/$courseId/enrollments');
    return data
        .map((item) => Enrollment.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Enrollment> enroll(int courseId, String studentUserId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/courses/$courseId/enrollments',
      data: {'student_user_id': studentUserId},
    );
    return Enrollment.fromJson(data);
  }

  /// Enrols a whole roll list. A batch commits once but reports per id: an unknown or
  /// duplicate entry is an outcome to show the teacher, not a failure of the request.
  Future<BulkEnrolmentResult> enrollBulk(int courseId, List<String> studentUserIds) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/courses/$courseId/enrollments/bulk',
      data: {'student_user_ids': studentUserIds},
    );
    return BulkEnrolmentResult.fromJson(data);
  }

  Future<void> unenroll(int courseId, int studentId) =>
      _api.delete('/courses/$courseId/enrollments/$studentId');
}
