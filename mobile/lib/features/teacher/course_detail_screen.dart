<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/providers/exam_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// A course and the exams inside it. This is where a teacher starts an exam.
class CourseDetailScreen extends ConsumerWidget {
  const CourseDetailScreen({super.key, required this.courseId});

  final int courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(courseProvider);
    final exams = ref.watch(courseExamsProvider(courseId));

    final course = courses.valueOrNull?.items
        .where((item) => item.id == courseId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(course?.courseCode ?? 'Course'),
        actions: [
          IconButton(
            key: const Key('course_enrollments'),
            tooltip: 'Enrolled students',
            onPressed: () => context.push(Routes.teacherCourseEnrollments(courseId)),
            icon: const Icon(Icons.group_outlined),
          ),
          IconButton(
            key: const Key('edit_course'),
            tooltip: 'Edit course',
            onPressed: () async {
              await context.push(Routes.teacherCourseEdit(courseId));
              ref.invalidate(courseProvider);
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
        bottom: course == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      course.courseName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_exam_fab'),
        onPressed: () => context.push(Routes.teacherExamCreate(courseId)),
        icon: const Icon(Icons.add),
        label: const Text('Create Exam'),
      ),
      body: exams.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load exams.',
          onRetry: () => ref.invalidate(courseExamsProvider(courseId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No exams yet',
              subtitle: 'Create an exam, add questions to it, then publish it.',
              icon: Icons.assignment_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(courseExamsProvider(courseId).future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => ExamTile(
                exam: items[index],
                onTap: () => context.push(Routes.teacherExam(items[index].id)),
              ),
            ),
          );
        },
      ),
    );
  }
}
=======
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/providers/exam_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// A course and the exams inside it. This is where a teacher starts an exam.
class CourseDetailScreen extends ConsumerWidget {
  const CourseDetailScreen({super.key, required this.courseId});

  final int courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(courseProvider);
    final exams = ref.watch(courseExamsProvider(courseId));

    final course = courses.valueOrNull?.items
        .where((item) => item.id == courseId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(course?.courseCode ?? 'Course'),
        actions: [
          IconButton(
            key: const Key('course_enrollments'),
            tooltip: 'Enrolled students',
            onPressed: () => context.push(Routes.teacherCourseEnrollments(courseId)),
            icon: const Icon(Icons.group_outlined),
          ),
          IconButton(
            key: const Key('edit_course'),
            tooltip: 'Edit course',
            onPressed: () async {
              await context.push(Routes.teacherCourseEdit(courseId));
              ref.invalidate(courseProvider);
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
        bottom: course == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      course.courseName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_exam_fab'),
        onPressed: () => context.push(Routes.teacherExamCreate(courseId)),
        icon: const Icon(Icons.add),
        label: const Text('Create Exam'),
      ),
      body: exams.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load exams.',
          onRetry: () => ref.invalidate(courseExamsProvider(courseId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No exams yet',
              subtitle: 'Create an exam, add questions to it, then publish it.',
              icon: Icons.assignment_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(courseExamsProvider(courseId).future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => ExamTile(
                exam: items[index],
                onTap: () => context.push(Routes.teacherExam(items[index].id)),
              ),
            ),
          );
        },
      ),
    );
  }
}
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
