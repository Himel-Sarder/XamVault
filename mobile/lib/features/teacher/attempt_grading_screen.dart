import 'package:flutter/material.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/exam_result.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// One student's written answers, and the marks a teacher awards them (§21, §22).
class AttemptGradingScreen extends ConsumerWidget {
  const AttemptGradingScreen({super.key, required this.examId, required this.attemptId});

  final int examId;
  final int attemptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grading = ref.watch(attemptGradingProvider(attemptId));

    return Scaffold(
      appBar: AppBar(title: const Text('Mark answers')),
      body: grading.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this paper.',
          onRetry: () => ref.invalidate(attemptGradingProvider(attemptId)),
        ),
        data: (data) {
          if (data.answers.isEmpty) {
            return const EmptyView(
              title: 'Nothing to mark',
              subtitle: 'This paper had no written questions; it was marked automatically.',
              icon: Icons.task_alt,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: Text(data.studentName),
                  subtitle: Text(data.examTitle),
                  trailing: Text(
                    data.awaitingMarks == 0 ? 'Done' : '${data.awaitingMarks} left',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final answer in data.answers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AnswerMarkingCard(
                    examId: examId,
                    attemptId: attemptId,
                    answer: answer,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AnswerMarkingCard extends ConsumerStatefulWidget {
  const AnswerMarkingCard({
    super.key,
    required this.examId,
    required this.attemptId,
    required this.answer,
  });

  final int examId;
  final int attemptId;
  final AnswerToMark answer;

  @override
  ConsumerState<AnswerMarkingCard> createState() => _AnswerMarkingCardState();
}

class _AnswerMarkingCardState extends ConsumerState<AnswerMarkingCard> {
  late final TextEditingController _marks;
  late final TextEditingController _feedback;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final awarded = widget.answer.marksAwarded;
    _marks = TextEditingController(
      text: awarded == null
          ? ''
          : (awarded % 1 == 0 ? awarded.toInt().toString() : awarded.toString()),
    );
    _feedback = TextEditingController(text: widget.answer.feedback ?? '');
  }

  @override
  void dispose() {
    _marks.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final answerId = widget.answer.answerId;
    if (answerId == null) return;

    final marks = double.tryParse(_marks.text.trim());
    if (marks == null) {
      setState(() => _error = 'Enter a number of marks');
      return;
    }
    // The server re-checks this against the frozen question; the local check only saves
    // a round trip.
    if (marks < 0 || marks > widget.answer.maxMarks) {
      setState(() => _error = 'Marks must be between 0 and ${widget.answer.maxMarks}');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(examRepositoryProvider).evaluateAnswer(
            widget.attemptId,
            answerId,
            marksAwarded: marks,
            feedback: _feedback.text.trim().isEmpty ? null : _feedback.text.trim(),
          );
      ref.invalidate(attemptGradingProvider(widget.attemptId));
      ref.invalidate(gradingQueueProvider(widget.examId));
      ref.invalidate(examResultsProvider(widget.examId));
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answer = widget.answer;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Question ${answer.position}'
                    '${answer.isCode ? ' · code' : ' · short answer'}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (answer.isMarked)
                  Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 8),
            Text(answer.questionText, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: !answer.wasAnswered
                  ? Text(
                      'Not answered',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    )
                  : answer.isPhoto
                      // Tap to open full screen: a thumbnail cannot show whether the
                      // handwriting is legible, which is the whole question here.
                      ? _Photographs(urls: answer.answerImageUrls)
                      : SelectableText(
                          answer.answerText!,
                          style: answer.isCode
                              ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
                              : theme.textTheme.bodyMedium,
                        ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: Key('marks_${answer.examQuestionId}'),
                    controller: _marks,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Marks',
                      suffixText: '/ ${answer.maxMarks}',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: Key('feedback_${answer.examQuestionId}'),
                    controller: _feedback,
                    decoration: const InputDecoration(
                      labelText: 'Feedback (optional)',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: Key('save_marks_${answer.examQuestionId}'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: InlineLoader(size: 18),
                      )
                    : Text(answer.isMarked ? 'Update marks' : 'Award marks'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photographs a student took of their work, for the marker to read.
class _Photographs extends StatelessWidget {
  const _Photographs({required this.urls});

  final List<String> urls;

  void _open(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Photo ${index + 1} of ${urls.length}'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.network(AppConfig.mediaUrl(urls[index])),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${urls.length} photo${urls.length == 1 ? '' : 's'} — tap to enlarge',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => GestureDetector(
              key: Key('marker_photo_$index'),
              onTap: () => _open(context, index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  AppConfig.mediaUrl(urls[index]),
                  width: 140,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => Container(
                    width: 140,
                    height: 160,
                    alignment: Alignment.center,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Text('Could not load'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
