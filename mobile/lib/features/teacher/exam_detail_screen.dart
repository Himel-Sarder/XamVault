import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/providers/exam_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// One exam: its schedule, settings, questions, and the Publish action.
class ExamDetailScreen extends ConsumerWidget {
  const ExamDetailScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examProvider(examId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam'),
        actions: [
          if (exam.valueOrNull?.isEditable ?? false)
            IconButton(
              key: const Key('edit_exam'),
              tooltip: 'Edit exam',
              onPressed: () => context.push(Routes.teacherExamEdit(examId)),
              icon: const Icon(Icons.edit_outlined),
            ),
          // Requests only exist once students can see the exam, i.e. after publishing.
          if (exam.valueOrNull?.isEditable ?? false)
            IconButton(
              key: const Key('add_from_bank'),
              tooltip: 'Add from question bank',
              onPressed: () async {
                await context.push(Routes.teacherExamBankPicker(examId));
                refreshExam(ref, examId, courseId: exam.valueOrNull?.courseId);
              },
              icon: const Icon(Icons.inventory_2_outlined),
            ),
          if (!(exam.valueOrNull?.isDraft ?? true))
            IconButton(
              key: const Key('view_join_requests'),
              tooltip: 'Join requests',
              onPressed: () => context.push(Routes.teacherExamRequests(examId)),
              icon: const Icon(Icons.how_to_reg_outlined),
            ),
        ],
      ),
      body: exam.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this exam.',
          onRetry: () => ref.invalidate(examProvider(examId)),
        ),
        data: (data) => _ExamBody(exam: data),
      ),
      floatingActionButton: (exam.valueOrNull?.isEditable ?? false)
          ? FloatingActionButton.extended(
              key: const Key('add_question_fab'),
              onPressed: () async {
                await context.push(Routes.teacherQuestionNew(examId));
                refreshExam(ref, examId, courseId: exam.valueOrNull?.courseId);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Question'),
            )
          : null,
    );
  }
}

class _ExamBody extends ConsumerWidget {
  const _ExamBody({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final questions = ref.watch(examQuestionsProvider(exam.id));

    return RefreshIndicator(
      onRefresh: () async {
        refreshExam(ref, exam.id, courseId: exam.courseId);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _Header(exam: exam),
          const SizedBox(height: 16),
          if (exam.isDraft) _PublishCard(exam: exam),
          if (!exam.isDraft)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                    title: const Text('Published'),
                    subtitle: Text(
                      'Published ${formatDateTime(exam.publishedAt)}. '
                      'The questions are frozen and can no longer be changed.',
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('join_requests_row'),
                    leading: const Icon(Icons.how_to_reg_outlined),
                    title: const Text('Join requests'),
                    subtitle: const Text('Approve the students who may sit this exam'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.teacherExamRequests(exam.id)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('analytics_row'),
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Analytics'),
                    subtitle: const Text('Scores, distribution and question accuracy'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.teacherExamAnalytics(exam.id)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('grading_row'),
                    leading: const Icon(Icons.rate_review_outlined),
                    title: const Text('Marking'),
                    subtitle: const Text('Award marks for short answers and code'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.teacherExamGrading(exam.id)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('results_row'),
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Results'),
                    subtitle: const Text('Marks so far, and releasing them to students'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.teacherExamResults(exam.id)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          _SettingsSummary(settings: exam.settings),
          const SizedBox(height: 24),
          Text('Questions', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          questions.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: LoadingView(),
            ),
            error: (error, _) => ErrorView(
              message:
                  error is ApiException ? error.message : 'Could not load the questions.',
              onRetry: () => ref.invalidate(examQuestionsProvider(exam.id)),
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyView(
                      title: 'No questions yet',
                      subtitle: 'An exam needs at least one question before it can be '
                          'published.',
                      icon: Icons.help_outline,
                    ),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _QuestionCard(exam: exam, item: item),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(exam.title, style: theme.textTheme.titleLarge)),
                ExamStatusChip(status: exam.status),
              ],
            ),
            if (exam.description != null && exam.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(exam.description!, style: theme.textTheme.bodyMedium),
            ],
            const Divider(height: 24),
            _row(context, Icons.event_outlined, 'Starts',
                formatDateTime(exam.startAt, ifNull: 'Not set')),
            _row(context, Icons.timer_outlined, 'Duration', '${exam.durationMinutes} minutes'),
            if (exam.expiresAt != null)
              _row(context, Icons.event_busy_outlined, 'Ends',
                  formatDateTime(exam.expiresAt)),
            _row(context, Icons.star_outline, 'Total marks', '${exam.totalMarks}'),
            _row(context, Icons.help_outline, 'Questions', '${exam.questionCount}'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Publish, with the reasons it is blocked shown up front.
///
/// The server re-runs every one of these checks; showing them here saves the teacher a
/// round of trial and error, it does not replace the validation.
class _PublishCard extends ConsumerStatefulWidget {
  const _PublishCard({required this.exam});

  final Exam exam;

  @override
  ConsumerState<_PublishCard> createState() => _PublishCardState();
}

class _PublishCardState extends ConsumerState<_PublishCard> {
  bool _publishing = false;

  Future<void> _publish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publish this exam?'),
        content: const Text(
          'Students enrolled in this course will be able to see it. Once published, the '
          'questions are frozen and the exam can no longer be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _publishing = true);
    try {
      await ref.read(examRepositoryProvider).publish(widget.exam.id);
      refreshExam(ref, widget.exam.id, courseId: widget.exam.courseId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exam published')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      refreshExam(ref, widget.exam.id, courseId: widget.exam.courseId);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final check = ref.watch(publishCheckProvider(widget.exam.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: check.when(
          loading: () => const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            error is ApiException ? error.message : 'Could not check this exam.',
          ),
          data: (result) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!result.canPublish) ...[
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text('Not ready to publish', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                for (final issue in result.issues)
                  Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 4),
                    child: Text(
                      '• ${issue.message}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('publish_exam'),
                  onPressed: (!result.canPublish || _publishing) ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.publish_outlined),
                  label: const Text('Publish exam'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({required this.settings});

  final ExamSettings? settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = settings;
    if (value == null) return const SizedBox.shrink();

    final entries = <(String, bool)>[
      ('Shuffle questions', value.shuffleQuestions),
      ('Shuffle answers', value.shuffleAnswers),
      ('Allow going back', value.allowBackNavigation),
      ('Auto submit', value.autoSubmit),
      ('Secure mode', value.secureMode),
      ('Show result immediately', value.showResultImmediately),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settings', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                for (final (label, enabled) in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          enabled ? Icons.check_circle_outline : Icons.remove_circle_outline,
                          size: 18,
                          color: enabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.repeat, size: 18, color: theme.colorScheme.outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Maximum attempts: ${value.maxAttempts}',
                            style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends ConsumerWidget {
  const _QuestionCard({required this.exam, required this.item});

  final Exam exam;
  final ExamQuestion item;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this question?'),
        content: const Text('It will be deleted from this exam.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    try {
      await ref.read(examRepositoryProvider).removeQuestion(exam.id, item.id);
      refreshExam(ref, exam.id, courseId: exam.courseId);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final question = item.question;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    '${item.displayOrder + 1}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(question.questionText, style: theme.textTheme.bodyLarge),
                ),
                if (exam.isEditable)
                  PopupMenuButton<String>(
                    key: Key('question_menu_${item.id}'),
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await context
                            .push(Routes.teacherQuestionEdit(exam.id, item.id));
                        refreshExam(ref, exam.id, courseId: exam.courseId);
                      } else if (action == 'delete') {
                        await _delete(context, ref);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Remove')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 40, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final option in question.options)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            option.isCorrect
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 16,
                            // The answer key is teacher-only; no student schema carries it.
                            color: option.isCorrect
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              option.optionText ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight:
                                    option.isCorrect ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${item.marks} mark${item.marks == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (question.difficulty != null) ...[
                        const SizedBox(width: 12),
                        Text('· ${question.difficulty}',
                            style: theme.textTheme.bodySmall),
                      ],
                      if (item.isFrozen) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.lock_outline,
                            size: 14, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('Frozen', style: theme.textTheme.bodySmall),
                      ],
                    ],
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
