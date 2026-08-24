import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/student/widgets/student_exam_tile.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/providers/student_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

class MyRequestsScreen extends ConsumerWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(myRequestsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('My Requests')),
      body: requests.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load your requests.',
          onRetry: () => ref.invalidate(myRequestsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No requests yet',
              subtitle: 'Open an available exam and ask your teacher to admit you.',
              icon: Icons.fact_check_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(myRequestsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final request = items[index];
                return Card(
                  child: ListTile(
                    onTap: () => context.push(Routes.studentExam(request.examId)),
                    title: Text(request.examTitle),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '${request.courseCode} · asked '
                          '${formatDateTime(request.requestedAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        JoinStatusChip(status: request.status),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
