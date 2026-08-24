import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// The shell all three dashboards share: identity header, a courses preview and the
/// account menu. Only the wording and the destination of "view all" differ per role.
class DashboardScaffold extends ConsumerWidget {
  const DashboardScaffold({
    super.key,
    required this.title,
    required this.coursesLabel,
    required this.coursesRoute,
    required this.emptyCoursesMessage,
    this.actions = const [],
  });

  final String title;
  final String coursesLabel;
  final String? coursesRoute;
  final String emptyCoursesMessage;

  /// Extra app-bar actions, before the profile button.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final courses = ref.watch(courseProvider);

    if (user == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...actions,
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.push(Routes.profile),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(courseProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            IdentityCard(user: user),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    coursesLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (coursesRoute != null && courses.valueOrNull?.items.isNotEmpty == true)
                  TextButton(
                    onPressed: () => context.push(coursesRoute!),
                    child: const Text('View all'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            courses.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: LoadingView(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ErrorView(
                  message: error.toString().replaceFirst('ApiException: ', ''),
                  onRetry: () => ref.invalidate(courseProvider),
                ),
              ),
              data: (page) => page.items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: EmptyView(
                        title: 'No courses yet',
                        subtitle: emptyCoursesMessage,
                        icon: Icons.menu_book_outlined,
                      ),
                    )
                  : Column(
                      children: [
                        for (final course in page.items.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CourseTile(
                              course: course,
                              onTap: user.isTeacher
                                  ? () => context.push(Routes.teacherCourse(course.id))
                                  : null,
                            ),
                          ),
                        if (page.total > 4)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Showing 4 of ${page.total}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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

/// Shared by all three dashboards.
class IdentityCard extends ConsumerWidget {
  const IdentityCard({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle = switch (user.role) {
      UserRole.student =>
        'Student ID ${user.studentProfile?.studentId ?? user.userId}'
            '${user.studentProfile?.semester != null ? ' · Semester ${user.studentProfile!.semester}' : ''}',
      UserRole.teacher =>
        '${user.teacherProfile?.designation ?? 'Teacher'} · ID ${user.teacherProfile?.teacherId ?? user.userId}',
      UserRole.admin => 'Administrator · ID ${user.userId}',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                _initials(user.name),
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class CourseTile extends StatelessWidget {
  const CourseTile({super.key, required this.course, this.onTap});

  final Course course;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(Icons.menu_book_outlined,
              color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(course.courseCode),
        subtitle: Text(
          [
            course.courseName,
            if (course.session != null) course.session!,
          ].join(' · '),
        ),
        trailing: course.isActive
            ? null
            : Chip(
                label: const Text('Archived'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
      ),
    );
  }
}
