import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/bank_question.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/providers/exam_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/config/semantic_colours.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/status_pill.dart';
import 'package:uniexam/widgets/status_views.dart';

/// The teacher's reusable question library (§6).
///
/// Serves two purposes from one screen: browsing and curating the library, and — when
/// [selectionFor] is set — picking questions to add to a draft exam.
class QuestionBankScreen extends ConsumerStatefulWidget {
  const QuestionBankScreen({super.key, this.selectionFor});

  /// The exam to add the chosen questions to, when opened as a picker.
  final int? selectionFor;

  bool get isPicking => selectionFor != null;

  @override
  ConsumerState<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends ConsumerState<QuestionBankScreen> {
  final _search = TextEditingController();
  final Set<int> _selected = {};

  QuestionType? _type;
  String? _difficulty;
  String? _topic;
  String _query = '';
  bool _attaching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  BankFilter get _filter => (
        type: _type,
        difficulty: _difficulty,
        topic: _topic,
        search: _query.trim().isEmpty ? null : _query.trim(),
      );

  Future<void> _attach() async {
    setState(() => _attaching = true);
    try {
      await ref.read(questionBankRepositoryProvider).attachToExam(
            widget.selectionFor!,
            _selected.toList(),
          );
      refreshExam(ref, widget.selectionFor!);
      if (mounted) Navigator.of(context).pop(_selected.length);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<void> _delete(BankQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this question?'),
        content: const Text('It will be removed from your library for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    try {
      await ref.read(questionBankRepositoryProvider).delete(question.id);
      ref.invalidate(questionBankProvider);
      ref.invalidate(bankTopicsProvider);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = ref.watch(questionBankProvider(_filter));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPicking ? 'Choose questions' : 'Question Bank'),
      ),
      body: Column(
        children: [
          _filters(),
          Expanded(
            child: questions.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorView(
                message:
                    error is ApiException ? error.message : 'Could not load your library.',
                onRetry: () => ref.invalidate(questionBankProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyView(
                    title: _hasFilters ? 'Nothing matches' : 'Your library is empty',
                    subtitle: _hasFilters
                        ? 'Try a different filter or search term.'
                        : 'Questions you write here can be reused across exams and terms.',
                    icon: Icons.inventory_2_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _questionCard(items[index]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.isPicking
          ? FloatingActionButton.extended(
              key: const Key('attach_selected'),
              onPressed: _selected.isEmpty || _attaching ? null : _attach,
              icon: _attaching
                  ? const SizedBox(
                      height: 18, width: 18, child: InlineLoader(size: 18))
                  : const Icon(Icons.playlist_add),
              label: Text(
                _selected.isEmpty
                    ? 'Select questions'
                    : 'Add ${_selected.length} to exam',
              ),
            )
          : null,
    );
  }

  bool get _hasFilters =>
      _type != null || _difficulty != null || _topic != null || _query.trim().isNotEmpty;

  Widget _filters() {
    final topics = ref.watch(bankTopicsProvider).valueOrNull ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          TextField(
            key: const Key('bank_search'),
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search question text',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  label: _type?.label ?? 'Any type',
                  active: _type != null,
                  onTap: () => _pickType(),
                ),
                const SizedBox(width: 8),
                _chip(
                  label: _difficulty ?? 'Any difficulty',
                  active: _difficulty != null,
                  onTap: () => _pickDifficulty(),
                ),
                if (topics.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _chip(
                    label: _topic ?? 'Any topic',
                    active: _topic != null,
                    onTap: () => _pickTopic(topics),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required bool active, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ActionChip(
      label: Text(label),
      avatar: Icon(
        active ? Icons.filter_alt : Icons.filter_alt_outlined,
        size: 16,
        color: active ? theme.colorScheme.onSecondaryContainer : null,
      ),
      backgroundColor: active ? theme.colorScheme.secondaryContainer : null,
      onPressed: onTap,
    );
  }

  Future<void> _pickType() async {
    final chosen = await _choose<QuestionType?>(
      'Question type',
      [
        (null, 'Any type'),
        for (final type in QuestionType.values) (type, type.label),
      ],
      _type,
    );
    if (mounted) setState(() => _type = chosen);
  }

  Future<void> _pickDifficulty() async {
    final chosen = await _choose<String?>(
      'Difficulty',
      const [(null, 'Any difficulty'), ('easy', 'Easy'), ('medium', 'Medium'), ('hard', 'Hard')],
      _difficulty,
    );
    if (mounted) setState(() => _difficulty = chosen);
  }

  Future<void> _pickTopic(List<String> topics) async {
    final chosen = await _choose<String?>(
      'Topic',
      [(null, 'Any topic'), for (final topic in topics) (topic, topic)],
      _topic,
    );
    if (mounted) setState(() => _topic = chosen);
  }

  /// A sheet rather than a dropdown: the option lists are short but the labels are long.
  Future<T?> _choose<T>(String title, List<(T, String)> options, T current) async {
    return showModalBottomSheet<T>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final (value, label) in options)
              ListTile(
                title: Text(label),
                trailing: value == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _questionCard(BankQuestion question) {
    final theme = Theme.of(context);
    final selected = _selected.contains(question.id);

    return Card(
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        key: Key('bank_question_${question.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: !widget.isPicking
            ? null
            : () => setState(() {
                  selected ? _selected.remove(question.id) : _selected.add(question.id);
                }),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.isPicking)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
                      ),
                    ),
                  // The type is what a teacher filters and scans by, so it reads as a
                  // marked chip rather than a word in a row of words.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _TypeChip(type: question.type),
                    ),
                  ),
                  StatusPill(
                    label: '${question.marks} marks',
                    colour: context.status.success,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                question.questionText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (question.topic != null)
                    Chip(
                      label: Text(question.topic!),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  if (question.difficulty != null)
                    Chip(
                      label: Text(question.difficulty!),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  Text(
                    question.usedInExams == 0
                        ? 'Not used yet'
                        : 'Used in ${question.usedInExams} exam'
                            '${question.usedInExams == 1 ? '' : 's'}'
                            '${question.usedInPublished ? ' (one published)' : ''}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (!widget.isPicking)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: Key('delete_bank_question_${question.id}'),
                    // Refused server-side too; disabling here just avoids a pointless tap.
                    onPressed: question.isDeletable ? () => _delete(question) : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(question.isDeletable ? 'Delete' : 'In use'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The question's type, in its own colour. The same colour is used by the filter row
/// above, so choosing a filter and recognising a result are the same visual act.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final QuestionType type;

  @override
  Widget build(BuildContext context) {
    final colour = type.colour(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colour.container,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 14, color: colour.foreground),
          const SizedBox(width: 5),
          Text(
            type.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colour.foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
