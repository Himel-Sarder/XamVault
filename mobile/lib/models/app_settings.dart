/// The handful of things an administrator sets about this installation.
class AppSettings {
  const AppSettings({required this.universityName});

  /// Printed at the top of every report and shown on the dashboard.
  final String universityName;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        universityName: json['university_name'] as String? ?? 'University',
      );
}
