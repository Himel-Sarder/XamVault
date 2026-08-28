import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/features/shared/notifications_screen.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/status_pill.dart';
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
          const NotificationBell(),
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

    // The one surface in the app that carries identity rather than content, so it is
    // the one place a gradient earns its keep. Everything a candidate has to *read*
    // stays on a plain surface.
    return Container(
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white38),
            ),
            child: Text(
              _initials(user.name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    user.role.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    // Its own colour, derived from the code, so the same course looks the same
    // everywhere and a list of six is scannable rather than six identical rows.
    final accent = context.accents.forKey(course.courseCode);
    final archived = !course.isActive;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // A stripe rather than a tinted card: the colour identifies the course
          // without washing the text it sits beside.
          Container(width: 5, height: 72, color: accent.foreground),
          Expanded(
            child: ListTile(
              onTap: onTap,
              leading: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.container,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _shortCode(course.courseCode),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent.foreground,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              title: Text(
                course.courseCode,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                [
                  course.courseName,
                  // Who runs it, where an admin is looking at every course in the
                  // system and the name is the thing that tells them apart.
                  if (course.teacherName != null) course.teacherName!,
                  if (course.session != null) course.session!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: archived
                  ? StatusPill(label: 'Archived', colour: context.status.neutral)
                  : (onTap == null
                      ? null
                      : Icon(Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }

  /// The letters a reader actually uses to tell courses apart — "CSE-301" reads as
  /// "301" in a list where everything starts with CSE.
  static String _shortCode(String code) {
    final digits = RegExp(r'\d{2,}').firstMatch(code)?.group(0);
    if (digits != null) return digits.substring(0, digits.length.clamp(0, 3));
    final cleaned = code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return cleaned.isEmpty
        ? '?'
        : cleaned.substring(0, cleaned.length < 3 ? cleaned.length : 3).toUpperCase();
  }
}
