import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/features/shared/dashboard_scaffold.dart';

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashboardScaffold(
      title: 'Teacher Dashboard',
      coursesLabel: 'My Courses',
      coursesRoute: Routes.teacherCourses,
      emptyCoursesMessage:
          'Courses you create will appear here. An administrator can also assign them to you.',
      actions: [
        IconButton(
          key: const Key('open_question_bank'),
          tooltip: 'Question bank',
          onPressed: () => context.push(Routes.teacherQuestionBank),
          icon: const Icon(Icons.inventory_2_outlined),
        ),
      ],
    );
  }
}
