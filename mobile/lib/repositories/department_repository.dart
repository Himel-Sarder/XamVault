import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/department.dart';

/// Departments. Readable by any signed-in user — a course form needs the list — but
/// only an admin may write, which the API enforces.
class DepartmentRepository {
  const DepartmentRepository(this._api);

  final ApiClient _api;

  Future<List<Department>> list() async {
    final data = await _api.get<List<dynamic>>('/departments');
    return data
        .map((item) => Department.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Department> create({required String code, required String name}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/departments',
      data: {'code': code, 'name': name},
    );
    return Department.fromJson(data);
  }

  /// The code is absent by design: it is the stable handle other records refer to,
  /// so the API does not accept a change to it.
  Future<Department> update(int id, {String? name, bool? isActive}) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/departments/$id',
      data: {'name': ?name, 'is_active': ?isActive},
    );
    return Department.fromJson(data);
  }

  /// Who would lose their department. Read before the confirmation.
  Future<DepartmentDeletionImpact> deletionImpact(int id) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/departments/$id/deletion-impact',
    );
    return DepartmentDeletionImpact.fromJson(data);
  }

  Future<void> delete(int id) => _api.delete('/departments/$id');
}
