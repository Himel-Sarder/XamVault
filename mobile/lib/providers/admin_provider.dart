import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/providers.dart';

typedef UserFilter = ({UserRole? role, String? search});

/// The user directory, filtered. Admin-only at the API — this provider simply asks.
final adminUsersProvider =
    FutureProvider.autoDispose.family<Paged<User>, UserFilter>((ref, filter) async {
  return ref.watch(adminRepositoryProvider).users(
        role: filter.role,
        search: filter.search,
        pageSize: 50,
      );
});

/// Every teacher, for the "who runs this course" picker.
///
/// Not autoDispose: a course form and an assignment dialog both want it, and staff
/// lists change far more slowly than the screens that read them.
final teachersProvider = FutureProvider<List<User>>((ref) async {
  final page = await ref.watch(adminRepositoryProvider).users(
        role: UserRole.teacher,
        pageSize: 100,
      );
  return page.items;
});
