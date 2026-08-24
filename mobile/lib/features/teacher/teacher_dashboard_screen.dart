import 'package:flutter/material.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/features/shared/dashboard_scaffold.dart';

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardScaffold(
      title: 'Teacher Dashboard',
      coursesLabel: 'My Courses',
      coursesRoute: Routes.teacherCourses,
      emptyCoursesMessage:
          'Courses you create will appear here. An administrator can also assign them to you.',
    );
  }
}
