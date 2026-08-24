import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/features/shared/dashboard_scaffold.dart';

/// Administrators see every course, and the two registries everything else hangs off:
/// the people and the departments they belong to.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardScaffold(
      title: 'Administration',
      coursesLabel: 'All Courses',
      coursesRoute: Routes.adminCourses,
      emptyCoursesMessage: 'No courses have been created in the system yet.',
      actions: [
        IconButton(
          key: const Key('admin_users'),
          tooltip: 'Users',
          onPressed: () => context.push(Routes.adminUsers),
          icon: const Icon(Icons.group_outlined),
        ),
        IconButton(
          key: const Key('admin_departments'),
          tooltip: 'Departments',
          onPressed: () => context.push(Routes.adminDepartments),
          icon: const Icon(Icons.apartment_outlined),
        ),
      ],
    );
  }
}
