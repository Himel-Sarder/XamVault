import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/paged.dart';

/// Course reads. The backend already scopes the list by role, so there is nothing to
/// filter here — and nothing the client could widen.
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
}
