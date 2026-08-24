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
