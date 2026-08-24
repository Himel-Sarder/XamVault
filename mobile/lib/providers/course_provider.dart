import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

/// The caller's courses.
///
/// The backend decides what that means per role (enrolled / created / all), so both
/// dashboards can share this provider without either being able to widen its scope.
final courseProvider = FutureProvider.autoDispose<Paged<Course>>((ref) async {
  // The user id is a cache key, so switching account refetches instead of showing the
  // previous user's courses. Access itself is decided by the API, not here.
  ref.watch(authProvider.select((state) => state.user?.id));
  return ref.watch(courseRepositoryProvider).list();
});
