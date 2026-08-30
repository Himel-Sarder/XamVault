import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/shared/dashboard_scaffold.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/course_deletion_impact.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Full course list. The backend scopes it by role, so one screen serves everyone.
///
/// There is no archiving here any more. It was a second, softer kind of removal that
/// hid a course without saying where it went, and once deleting existed -- with the
/// count of what it would destroy shown first -- keeping both meant two answers to one
/// question. A course is on the list or it is gone.
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key, required this.title});

  final String title;

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  int? _busyId;

  Future<void> _confirmDelete(Course course) async {
    final courses = ref.read(courseRepositoryProvider);

    CourseDeletionImpact impact;
    try {
      impact = await courses.deletionImpact(course.id);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('delete_course_dialog'),
        title: const Text('Delete this course?'),
        content: Text(
          impact.isEmpty
              ? '${course.courseCode} - ${course.courseName} will be removed. '
                  'Nothing has been written on it yet, so nothing else goes with it.'
              : '${course.courseCode} - ${course.courseName} will be removed, and so '
                  'will its ${impact.losses.join(', ')}. Results other students '
                  'depend on are part of that. This cannot be undone.\n\n'
                  'Questions stay in their author\'s bank.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const Key('confirm_delete_course'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: impact.isEmpty
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: dialogContext.status.danger.foreground,
                    foregroundColor: Colors.white,
                  ),
            child: Text(impact.isEmpty ? 'Delete' : 'Delete everything'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _busyId = course.id);
    try {
      await courses.delete(course.id);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
        ref.invalidate(courseProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(courseProvider);
    final role = ref.watch(authProvider).user?.role;
    final isTeacher = role == UserRole.teacher;
    final isAdmin = role == UserRole.admin;
    // Both may create a course; the API says so, and each keeps to its own path prefix.
    final createRoute = isTeacher
        ? Routes.teacherCourseCreate
        : (isAdmin ? Routes.adminCourseCreate : null);
    // Whoever may manage a course may delete it, which is what the API enforces.
    final canDelete = isTeacher || isAdmin;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: createRoute == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('new_course'),
              onPressed: () async {
                await context.push(createRoute);
                ref.invalidate(courseProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('New course'),
            ),
      body: courses.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error.toString().replaceFirst('ApiException: ', ''),
          onRetry: () => ref.invalidate(courseProvider),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return const EmptyView(
              title: 'No courses',
              subtitle: 'Nothing to show here yet.',
              icon: Icons.menu_book_outlined,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(courseProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final course = page.items[index];
                return CourseTile(
                  course: course,
                  busy: _busyId == course.id,
                  onDelete: canDelete ? () => _confirmDelete(course) : null,
                  onTap: isTeacher
                      ? () => context.push(Routes.teacherCourse(course.id))
                      // An admin's job here is who runs it and who is on it, so the
                      // row opens the form that holds both rather than jumping
                      // straight to the roll.
                      : (isAdmin
                          ? () async {
                              await context.push(Routes.adminCourseEdit(course.id));
                              ref.invalidate(courseProvider);
                            }
                          : null),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
