import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/app_settings.dart';

/// Installation settings. Anyone signed in may read them; only an admin may write.
///
/// The write is refused server-side for everyone else, as usual — the admin-only
/// screen hides it, but hiding is not the control.
class SettingsRepository {
  const SettingsRepository(this._api);

  final ApiClient _api;

  Future<AppSettings> get() async {
    final data = await _api.get<Map<String, dynamic>>('/settings');
    return AppSettings.fromJson(data);
  }

  Future<AppSettings> setUniversityName(String name) async {
    final data = await _api.put<Map<String, dynamic>>(
      '/settings',
      data: {'university_name': name},
    );
    return AppSettings.fromJson(data);
  }
}
