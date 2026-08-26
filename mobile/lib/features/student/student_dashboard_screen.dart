import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/shared/dashboard_scaffold.dart';
import 'package:uniexam/features/shared/notifications_screen.dart';
import 'package:uniexam/features/student/widgets/student_exam_tile.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/providers/student_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// A student's home: who they are, what exams are coming, what they are enrolled in.
///
/// Exams come first because that is what a student opens the app for.
class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final exams = ref.watch(availableExamsProvider);
    final courses = ref.watch(courseProvider);
    final theme = Theme.of(context);

    if (user == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          const NotificationBell(),
          IconButton(
            key: const Key('my_results'),
            tooltip: 'My results',
            onPressed: () => context.push(Routes.studentResults),
            icon: const Icon(Icons.emoji_events_outlined),
          ),
          IconButton(
            key: const Key('my_requests'),
            tooltip: 'My requests',
            onPressed: () => context.push(Routes.studentRequests),
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.push(Routes.profile),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(availableExamsProvider);
          ref.invalidate(courseProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            IdentityCard(user: user),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Available Exams', style: theme.textTheme.titleMedium),
                ),
                if (exams.valueOrNull?.isNotEmpty ?? false)
                  TextButton(
                    onPressed: () => context.push(Routes.studentExams),
                    child: const Text('View all'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            exams.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LoadingView(),
              ),
              error: (error, _) => ErrorView(
                message: error is ApiException ? error.message : 'Could not load exams.',
                onRetry: () => ref.invalidate(availableExamsProvider),
              ),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: EmptyView(
                        title: 'No exams right now',
                        subtitle: 'Published exams for your courses appear here.',
                        icon: Icons.assignment_outlined,
                      ),
                    )
                  : Column(
                      children: [
                        for (final exam in items.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: StudentExamTile(
                              exam: exam,
                              onTap: () => context.push(Routes.studentExam(exam.id)),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Enrolled Courses', style: theme.textTheme.titleMedium),
                ),
                if (courses.valueOrNull?.items.isNotEmpty ?? false)
                  TextButton(
                    onPressed: () => context.push(Routes.studentCourses),
                    child: const Text('View all'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            courses.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LoadingView(),
              ),
              error: (error, _) => ErrorView(
                message: error is ApiException ? error.message : 'Could not load courses.',
                onRetry: () => ref.invalidate(courseProvider),
              ),
              data: (page) => page.items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: EmptyView(
                        title: 'No courses yet',
                        subtitle: 'Your department office or course teacher enrols you.',
                        icon: Icons.menu_book_outlined,
                      ),
                    )
                  : Column(
                      children: [
                        for (final course in page.items.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CourseTile(course: course),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
