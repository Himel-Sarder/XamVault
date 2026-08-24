import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/student/widgets/student_exam_tile.dart';
import 'package:uniexam/providers/student_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Every exam the student may sit. Scoped server-side to published exams in the courses
/// they are enrolled in, so this screen has nothing to filter.
class AvailableExamsScreen extends ConsumerWidget {
  const AvailableExamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(availableExamsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Exams'),
        actions: [
          IconButton(
            key: const Key('my_requests'),
            tooltip: 'My requests',
            onPressed: () => context.push(Routes.studentRequests),
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
      body: exams.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load your exams.',
          onRetry: () => ref.invalidate(availableExamsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No exams right now',
              subtitle: 'Exams appear here once your teacher publishes them for a course '
                  'you are enrolled in.',
              icon: Icons.assignment_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(availableExamsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => StudentExamTile(
                exam: items[index],
                onTap: () => context.push(Routes.studentExam(items[index].id)),
              ),
            ),
          );
        },
      ),
    );
  }
}
