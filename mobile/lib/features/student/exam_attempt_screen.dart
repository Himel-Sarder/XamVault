import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/exam_security.dart';
import 'package:uniexam/features/student/widgets/exam_timer.dart';
import 'package:uniexam/features/student/widgets/question_body.dart';
import 'package:uniexam/models/attempt.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// The exam itself: one question at a time, a palette to move around, a countdown, and
/// a submit that asks for confirmation. Deliberately spare — no drawer, no distractions
/// (§59).
class ExamAttemptScreen extends ConsumerWidget {
  const ExamAttemptScreen({super.key, required this.attemptId});

  final int attemptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(attemptControllerProvider(attemptId));

    return state.when(
      loading: () => const Scaffold(body: LoadingView(message: 'Loading your exam…')),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Exam')),
        body: ErrorView(
          message: error is ApiException ? error.message : 'Could not load this exam.',
          onRetry: () => ref.invalidate(attemptControllerProvider(attemptId)),
        ),
      ),
      data: (view) => view.isFinished
          ? SubmittedView(view: view)
          : _ExamView(view: view, attemptId: attemptId),
    );
  }
}

class _ExamView extends ConsumerStatefulWidget {
  const _ExamView({required this.view, required this.attemptId});

  final AttemptView view;
  final int attemptId;

  @override
  ConsumerState<_ExamView> createState() => _ExamViewState();
}

class _ExamViewState extends ConsumerState<_ExamView> {
  /// One controller per written question, kept across rebuilds so the caret does not
  /// jump while typing.
  final Map<int, TextEditingController> _writing = {};

  AttemptView get view => widget.view;
  int get attemptId => widget.attemptId;

  @override
  void dispose() {
    for (final controller in _writing.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(AttemptQuestion question) {
    final existing = _writing[question.examQuestionId];
    if (existing != null) return existing;
    final created = TextEditingController(text: question.answerText ?? '');
    _writing[question.examQuestionId] = created;
    return created;
  }

  Future<void> _confirmSubmit(BuildContext context, WidgetRef ref) async {
    final attempt = view.attempt;
    final unanswered = attempt.totalQuestions - attempt.answeredCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit this exam?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Answered: ${attempt.answeredCount} / ${attempt.totalQuestions}'),
            if (unanswered > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Unanswered: $unanswered',
                  style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            const Text('You cannot change your answers after submitting.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(attemptControllerProvider(attemptId).notifier).submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ref.read(attemptControllerProvider(attemptId).notifier);
    final attempt = view.attempt;
    final question = view.question;
    final answeredIndices = {
      for (var i = 0; i < attempt.questions.length; i++)
        if (attempt.questions[i].isAnswered) i,
    };

    return PopScope(
      // Leaving mid-exam by accident would be costly, so the back gesture is inert.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attempt.courseCode, style: theme.textTheme.labelMedium),
              Text(attempt.examTitle, style: theme.textTheme.titleMedium),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: ExamTimer(remainingSeconds: view.remainingSeconds)),
            ),
          ],
        ),
        body: Column(
          children: [
            LinearProgressIndicator(
              value: attempt.totalQuestions == 0
                  ? 0
                  : (view.index + 1) / attempt.totalQuestions,
            ),
            if (view.lockdown != null) _LockdownBanner(status: view.lockdown!),
            Expanded(child: _body(context, theme, controller, attempt, question, answeredIndices)),
            SafeArea(child: _footer(context, ref, controller, attempt)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ThemeData theme,
    AttemptController controller,
    Attempt attempt,
    AttemptQuestion question,
    Set<int> answeredIndices,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Question ${question.position} of ${attempt.totalQuestions}',
                style: theme.textTheme.labelLarge,
              ),
            ),
            Text(
              '${question.marks} mark${question.marks == 1 ? '' : 's'}',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(question.questionText, style: theme.textTheme.titleLarge),
        if (question.hasImageStem) ...[
          const SizedBox(height: 16),
          QuestionImage(path: question.questionImageUrl!),
        ],
        const SizedBox(height: 20),
        // The answer control follows the question type: options to choose from, a
        // writing area, or a code editor.
        if (question.isChoice)
          for (final option in question.options)
            OptionCard(
              option: option,
              selected: question.selectedOptionId == option.id,
              onTap: () => controller.select(question.examQuestionId, option.id),
            )
        else if (question.isCode)
          CodeAnswerField(
            question: question,
            controller: _controllerFor(question),
            onChanged: (text) => controller.write(question.examQuestionId, text),
          )
        else
          ShortAnswerField(
            controller: _controllerFor(question),
            onChanged: (text) => controller.write(question.examQuestionId, text),
          ),
        if (view.error != null) ...[
          const SizedBox(height: 12),
          Text(view.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Text('Question palette', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        QuestionPalette(
          total: attempt.totalQuestions,
          currentIndex: view.index,
          answered: answeredIndices,
          onSelect: controller.goTo,
        ),
      ],
    );
  }

  Widget _footer(
    BuildContext context,
    WidgetRef ref,
    AttemptController controller,
    Attempt attempt,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('previous_question'),
                  // Disabled outright when the teacher turned back navigation off.
                  onPressed: (view.isFirst || !attempt.allowBackNavigation)
                      ? null
                      : controller.previous,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('next_question'),
                  onPressed: view.isLast ? null : controller.next,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: const Key('submit_exam'),
              onPressed: view.submitting ? null : () => _confirmSubmit(context, ref),
              icon: view.submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                'Submit  ·  ${attempt.answeredCount}/${attempt.totalQuestions} answered',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once the attempt is closed — by the student, or by the clock running out.
class SubmittedView extends ConsumerWidget {
  const SubmittedView({super.key, required this.view});

  final AttemptView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final outcome = view.outcome;
    final attempt = view.attempt;
    final autoSubmitted = (outcome?.status ?? attempt.status) == AttemptStatus.autoSubmitted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submitted'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  autoSubmitted ? Icons.timer_off_outlined : Icons.check_circle_outline,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  autoSubmitted ? 'Time is up' : 'Exam submitted',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  autoSubmitted
                      ? 'Your answers were submitted automatically when the time ran out.'
                      : 'Your answers have been recorded.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row(theme, 'Exam', attempt.examTitle),
                        _row(theme, 'Course', attempt.courseCode),
                        _row(
                          theme,
                          'Answered',
                          '${outcome?.answeredCount ?? attempt.answeredCount}'
                              ' / ${outcome?.totalQuestions ?? attempt.totalQuestions}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  outcome?.resultId != null
                      ? 'Your result is ready.'
                      : 'Your result will appear once your teacher releases the marks.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('leave_exam'),
                    onPressed: () => context.go(Routes.studentHome),
                    child: const Text('Back to dashboard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}


/// States what the device actually protects, rather than implying more.
///
/// On a personal phone the honest answer is usually "screenshots blocked, and leaving
/// the app is recorded" — not "you cannot cheat" (§38).
class _LockdownBanner extends StatelessWidget {
  const _LockdownBanner({required this.status});

  final LockdownStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (icon, background, foreground, message) = status.isFullyLocked
        ? (
            Icons.lock,
            scheme.primaryContainer,
            scheme.onPrimaryContainer,
            'Device locked to this exam.',
          )
        : status.blocksScreenCapture
            ? (
                Icons.lock_outline,
                scheme.secondaryContainer,
                scheme.onSecondaryContainer,
                'Screenshots are blocked. Leaving the app is recorded.',
              )
            : (
                Icons.info_outline,
                scheme.surfaceContainerHighest,
                scheme.onSurfaceVariant,
                'Device lockdown is not available here. Activity is still recorded.',
              );

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        key: const Key('lockdown_banner'),
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
