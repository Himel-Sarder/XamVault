import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Who has submitted, and how much of each paper still needs a person to mark it.
class GradingQueueScreen extends ConsumerWidget {
  const GradingQueueScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(gradingQueueProvider(examId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Marking')),
      body: queue.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load submissions.',
          onRetry: () => ref.invalidate(gradingQueueProvider(examId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No submissions yet',
              subtitle: 'Papers appear here as students submit them.',
              icon: Icons.rate_review_outlined,
            );
          }
          final outstanding = items.where((entry) => !entry.isFullyMarked).length;
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(gradingQueueProvider(examId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      outstanding == 0 ? Icons.task_alt : Icons.pending_actions_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      outstanding == 0
                          ? 'Everything is marked'
                          : '$outstanding paper${outstanding == 1 ? '' : 's'} still to mark',
                    ),
                    subtitle: Text('${items.length} submitted'),
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        key: Key('grade_attempt_${entry.attemptId}'),
                        onTap: () => context.push(
                          Routes.teacherAttemptGrading(examId, entry.attemptId),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: entry.isFullyMarked
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.tertiaryContainer,
                          child: Icon(
                            entry.isFullyMarked ? Icons.check : Icons.edit_outlined,
                            size: 18,
                            color: entry.isFullyMarked
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                        title: Text(entry.studentName),
                        subtitle: Text(
                          '${entry.studentNumber} · submitted '
                          '${formatDateTime(entry.submittedAt)}',
                        ),
                        trailing: Text(
                          entry.isFullyMarked
                              ? '${entry.totalScore.toStringAsFixed(entry.totalScore % 1 == 0 ? 0 : 1)}'
                                  '/${entry.totalMarks}'
                              : '${entry.awaitingMarks} to mark',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
