/// Mirrors the backend's `{items, total, page, page_size}` envelope.
class Paged<T> {
  const Paged({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final rawItems = (json['items'] as List<dynamic>? ?? const []);
    return Paged<T>(
      items: rawItems
          .map((item) => itemFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      total: json['total'] as int? ?? rawItems.length,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? rawItems.length,
    );
  }

  static Paged<T> empty<T>() =>
      Paged<T>(items: const [], total: 0, page: 1, pageSize: 20);
}
