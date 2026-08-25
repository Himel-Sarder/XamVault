import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/section.dart';
import 'package:uniexam/widgets/status_pill.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Who has submitted, and how much of each paper still needs a person to mark it.
class GradingQueueScreen extends ConsumerWidget {
  const GradingQueueScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(gradingQueueProvider(examId));

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
                // Amber while work is outstanding, green once it is not. A teacher
                // opening this screen wants that answer before they read a word.
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Still to mark',
                        value: '$outstanding',
                        icon: Icons.pending_actions_outlined,
                        colour: outstanding == 0
                            ? context.status.success
                            : context.status.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricTile(
                        label: 'Submitted',
                        value: '${items.length}',
                        icon: Icons.inbox_rounded,
                        colour: context.status.info,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // The tiles give the number; this gives the sentence. A count alone
                // makes a reader do the pluralising, and it is what a screen reader
                // announces most usefully.
                Text(
                  outstanding == 0
                      ? 'Everything is marked'
                      : '$outstanding paper${outstanding == 1 ? '' : 's'} still to mark',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final entry in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        key: Key('grade_attempt_${entry.attemptId}'),
                        onTap: () => context.push(
                          Routes.teacherAttemptGrading(examId, entry.attemptId),
                        ),
                        leading: Builder(builder: (context) {
                          final tint = entry.isFullyMarked
                              ? context.status.success
                              : context.status.warning;
                          return Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tint.container,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              entry.isFullyMarked ? Icons.check : Icons.edit_outlined,
                              size: 19,
                              color: tint.foreground,
                            ),
                          );
                        }),
                        title: Text(entry.studentName),
                        subtitle: Text(
                          '${entry.studentNumber} · submitted '
                          '${formatDateTime(entry.submittedAt)}',
                        ),
                        trailing: StatusPill(
                          label: entry.isFullyMarked
                              ? '${entry.totalScore.toStringAsFixed(entry.totalScore % 1 == 0 ? 0 : 1)}'
                                  '/${entry.totalMarks}'
                              : '${entry.awaitingMarks} to mark',
                          colour: entry.isFullyMarked
                              ? context.status.success
                              : context.status.warning,
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
