import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/features/shared/dashboard_scaffold.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Full course list. The backend scopes it by role, so one screen serves everyone.
class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(courseProvider);
    final role = ref.watch(authProvider).user?.role;
    final isTeacher = role == UserRole.teacher;
    final isAdmin = role == UserRole.admin;
    // Both may create a course; the API says so, and each keeps to its own path prefix.
    final createRoute = isTeacher
        ? Routes.teacherCourseCreate
        : (isAdmin ? Routes.adminCourseCreate : null);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
              itemBuilder: (_, index) => CourseTile(
                course: page.items[index],
                onTap: isTeacher
                    ? () => context.push(Routes.teacherCourse(page.items[index].id))
                    // An admin's job here is who runs it and who is on it, so the row
                    // opens the form that holds both rather than jumping straight to
                    // the roll.
                    : (isAdmin
                        ? () async {
                            await context
                                .push(Routes.adminCourseEdit(page.items[index].id));
                            ref.invalidate(courseProvider);
                          }
                        : null),
              ),
            ),
          );
        },
      ),
    );
  }
}
