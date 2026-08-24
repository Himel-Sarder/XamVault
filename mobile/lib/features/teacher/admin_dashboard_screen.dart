import 'package:flutter/material.dart';
import 'package:uniexam/features/shared/dashboard_scaffold.dart';

/// Administrators see every course. User and department management is API-only for now
/// (see docs/api.md); the mobile admin tooling arrives with the later phases.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardScaffold(
      title: 'Administration',
      coursesLabel: 'All Courses',
      coursesRoute: null,
      emptyCoursesMessage: 'No courses have been created in the system yet.',
    );
  }
}
