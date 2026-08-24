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
    final isTeacher = ref.watch(authProvider).user?.role == UserRole.teacher;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
              padding: const EdgeInsets.all(16),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => CourseTile(
                course: page.items[index],
                onTap: isTeacher
                    ? () => context.push(Routes.teacherCourse(page.items[index].id))
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}
