import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/models/user.dart';

/// Administrator user management.
///
/// Kept apart from [AuthRepository], which speaks for the *current* user. These calls
/// act on other people's accounts and are admin-only at the API; mixing them into the
/// session repository would blur a boundary worth keeping sharp.
class AdminRepository {
  const AdminRepository(this._api);

  final ApiClient _api;

  Future<Paged<User>> users({
    int page = 1,
    int pageSize = 20,
    UserRole? role,
    String? search,
  }) async {
    final data = await _api.get<Map<String, dynamic>>('/users', query: {
      'page': page,
      'page_size': pageSize,
      'role': ?role?.name,
      'search': ?search,
    });
    return Paged.fromJson(data, User.fromJson);
  }

  Future<User> user(int id) async {
    final data = await _api.get<Map<String, dynamic>>('/users/$id');
    return User.fromJson(data);
  }

  /// The password travels once, on creation, and is never read back — no response
  /// schema in the API declares it.
  Future<User> createUser({
    required String userId,
    required String password,
    required String name,
    required UserRole role,
    String? email,
    int? departmentId,
    String? studentId,
    int? studyYear,
    int? semester,
    String? session,
    String? teacherId,
    String? designation,
  }) async {
    final data = await _api.post<Map<String, dynamic>>('/users', data: {
      'user_id': userId,
      'password': password,
      'name': name,
      'role': role.name,
      'email': ?email,
      'department_id': ?departmentId,
      'student_id': ?studentId,
      'study_year': ?studyYear,
      'semester': ?semester,
      'session': ?session,
      'teacher_id': ?teacherId,
      'designation': ?designation,
    });
    return User.fromJson(data);
  }

  Future<User> updateUser(
    int id, {
    String? name,
    String? email,
    int? departmentId,
    bool? isActive,
  }) async {
    final data = await _api.patch<Map<String, dynamic>>('/users/$id', data: {
      'name': ?name,
      'email': ?email,
      'department_id': ?departmentId,
      'is_active': ?isActive,
    });
    return User.fromJson(data);
  }

  /// What deleting this account would destroy, read before the confirmation so the
  /// numbers can be shown rather than discovered afterwards.
  Future<Map<String, int>> deletionImpact(int id) async {
    final data = await _api.get<Map<String, dynamic>>('/users/$id/deletion-impact');
    return data.map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  /// Removes a deactivated account and everything that cascades from it. Refused for
  /// an active account, for your own, and for anyone who authored exams.
  Future<void> deleteUser(int id) => _api.delete('/users/$id');
}
