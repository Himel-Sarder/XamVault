import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/models/enrollment.dart';
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

/// One course, for the form and the enrolment screen.
final courseDetailProvider =
    FutureProvider.autoDispose.family<Course, int>((ref, courseId) async {
  return ref.watch(courseRepositoryProvider).get(courseId);
});

/// Who is on the roll.
final enrollmentsProvider =
    FutureProvider.autoDispose.family<List<Enrollment>, int>((ref, courseId) async {
  return ref.watch(courseRepositoryProvider).enrollments(courseId);
});

/// Departments, for the pickers on the course and user forms.
///
/// Not autoDispose: this list is small, changes rarely and is read by several forms,
/// so refetching it on every screen entry would be waste.
final departmentsProvider = FutureProvider<List<Department>>((ref) async {
  return ref.watch(departmentRepositoryProvider).list();
});

/// Everything that goes stale when a course or its roll changes.
void refreshCourse(WidgetRef ref, int courseId) {
  ref.invalidate(courseProvider);
  ref.invalidate(courseDetailProvider(courseId));
  ref.invalidate(enrollmentsProvider(courseId));
}
