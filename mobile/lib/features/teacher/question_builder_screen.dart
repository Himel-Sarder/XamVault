import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/image_field.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/providers/exam_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/repositories/exam_repository.dart';
import 'package:uniexam/widgets/status_views.dart';

const minOptions = 2;
const maxOptions = 8;
const codeLanguages = ['c', 'cpp', 'java', 'python', 'javascript'];

/// One option being written, before the server assigns it an id.
class _DraftOption {
  _DraftOption({String initialText = '', this.imageUrl})
      : text = TextEditingController(text: initialText);

  final TextEditingController text;
  String? imageUrl;

  void dispose() => text.dispose();
}

/// Builder for every question type (§18-§22).
///
/// The form follows the chosen type: options appear only for the multiple-choice types,
/// an image picker only where the type needs one, and the code settings only for code.
class QuestionBuilderScreen extends ConsumerStatefulWidget {
  const QuestionBuilderScreen({
    super.key,
    required this.examId,
    required this.courseId,
    this.existing,
  });

  final int examId;
  final int courseId;
  final ExamQuestion? existing;

  bool get isEditing => existing != null;

  @override
  ConsumerState<QuestionBuilderScreen> createState() => _QuestionBuilderScreenState();
}

class _QuestionBuilderScreenState extends ConsumerState<QuestionBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _questionText;
  late final TextEditingController _marks;
  late final TextEditingController _topic;
  late List<_DraftOption> _options;

  QuestionType _type = QuestionType.textMcq;
  String? _questionImageUrl;
  int _correctIndex = 0;
  String? _difficulty;
  String _language = 'cpp';
  int _timeLimit = 2;
  int _memoryLimit = 256;
  bool _saving = false;
  String? _error;

  bool get _isChoice => const {
        QuestionType.textMcq,
        QuestionType.imageTextOptions,
        QuestionType.imageImageOptions,
      }.contains(_type);

  bool get _needsQuestionImage => const {
        QuestionType.imageTextOptions,
        QuestionType.imageImageOptions,
      }.contains(_type);

  bool get _optionsAreImages => _type == QuestionType.imageImageOptions;

  @override
  void initState() {
    super.initState();
    final question = widget.existing?.question;
    _questionText = TextEditingController(text: question?.questionText ?? '');
    _marks = TextEditingController(text: '${question?.marks ?? 1}');
    _topic = TextEditingController(text: question?.topic ?? '');
    _difficulty = question?.difficulty;
    _type = question?.type ?? QuestionType.textMcq;
    _questionImageUrl = question?.questionImageUrl;
    _language = question?.language ?? 'cpp';
    _timeLimit = question?.timeLimitSeconds ?? 2;
    _memoryLimit = question?.memoryLimitMb ?? 256;

    if (question != null && question.options.isNotEmpty) {
      _options = question.options
          .map((option) => _DraftOption(
                initialText: option.optionText ?? '',
                imageUrl: option.optionImageUrl,
              ))
          .toList();
      final correct = question.options.indexWhere((option) => option.isCorrect);
      _correctIndex = correct < 0 ? 0 : correct;
    } else {
      _options = List.generate(4, (_) => _DraftOption());
    }
  }

  @override
  void dispose() {
    _questionText.dispose();
    _marks.dispose();
    _topic.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_options.length >= maxOptions) return;
    setState(() => _options.add(_DraftOption()));
  }

  void _removeOption(int index) {
    if (_options.length <= minOptions) return;
    setState(() {
      _options.removeAt(index).dispose();
      if (_correctIndex >= _options.length) {
        _correctIndex = _options.length - 1;
      } else if (_correctIndex > index) {
        // Keep the marked answer pointing at the same option after the list shifts.
        _correctIndex -= 1;
      }
    });
  }

  String? _localProblem() {
    if (_needsQuestionImage && (_questionImageUrl == null || _questionImageUrl!.isEmpty)) {
      return 'This question type needs an image for the question itself';
    }
    if (!_isChoice) return null;

    if (_optionsAreImages) {
      if (_options.any((option) => option.imageUrl == null || option.imageUrl!.isEmpty)) {
        return 'Every option of this question type needs an image';
      }
      return null;
    }
    final texts = _options.map((option) => option.text.text.trim().toLowerCase()).toList();
    if (texts.any((text) => text.isEmpty)) return 'Every option needs text';
    if (texts.toSet().length != texts.length) {
      return 'Options must be different from one another';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final problem = _localProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final draft = QuestionDraft(
      type: _type,
      questionText: _questionText.text.trim(),
      questionImageUrl: _needsQuestionImage ? _questionImageUrl : null,
      marks: int.parse(_marks.text.trim()),
      difficulty: _difficulty,
      topic: _topic.text.trim(),
      language: _type == QuestionType.codeAnswer ? _language : null,
      timeLimitSeconds: _type == QuestionType.codeAnswer ? _timeLimit : null,
      memoryLimitMb: _type == QuestionType.codeAnswer ? _memoryLimit : null,
      options: !_isChoice
          ? const []
          : [
              for (var index = 0; index < _options.length; index++)
                QuestionOptionDraft(
                  optionText: _optionsAreImages ? null : _options[index].text.text.trim(),
                  optionImageUrl: _optionsAreImages ? _options[index].imageUrl : null,
                  isCorrect: index == _correctIndex,
                ),
            ],
    );

    try {
      final repository = ref.read(examRepositoryProvider);
      if (widget.isEditing) {
        await repository.updateQuestion(widget.examId, widget.existing!.id, draft);
      } else {
        await repository.addQuestion(widget.examId, draft);
      }
      refreshExam(ref, widget.examId, courseId: widget.courseId);
      if (mounted) context.pop(true);
    } on ApiException catch (error) {
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit Question' : 'Add Question')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            DropdownButtonFormField<QuestionType>(
              key: const Key('question_type'),
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Question type',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final type in QuestionType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() {
                _type = value ?? QuestionType.textMcq;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('question_text'),
              controller: _questionText,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Question',
                hintText: 'e.g. What is the time complexity of binary search?',
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Write the question' : null,
            ),
            if (_needsQuestionImage) ...[
              const SizedBox(height: 20),
              ImageField(
                fieldKey: const Key('question_image'),
                label: 'Question image',
                url: _questionImageUrl,
                onChanged: (url) => setState(() {
                  _questionImageUrl = url;
                  _error = null;
                }),
                height: 200,
              ),
            ],
            const SizedBox(height: 16),
            _marksAndDifficulty(),
            const SizedBox(height: 16),
            TextFormField(
              controller: _topic,
              decoration: const InputDecoration(
                labelText: 'Topic (optional)',
                hintText: 'e.g. Normalization',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            if (_type == QuestionType.codeAnswer) ...[
              const SizedBox(height: 24),
              Text('Code settings', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _codeSettings(),
            ],
            if (_isChoice) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Options', style: theme.textTheme.titleSmall)),
                  Text(
                    'Tap the circle to mark the answer',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // RadioGroup owns the selection, so "exactly one correct answer" is a
              // property of the widget tree rather than something to validate later.
              RadioGroup<int>(
                groupValue: _correctIndex,
                onChanged: (value) => setState(() => _correctIndex = value ?? 0),
                child: Column(
                  children: [
                    for (var index = 0; index < _options.length; index++) _optionRow(index),
                  ],
                ),
              ),
              if (_options.length < maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('add_option'),
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Add option'),
                  ),
                ),
            ] else ...[
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: Icon(Icons.rate_review_outlined, color: theme.colorScheme.primary),
                  title: const Text('Marked by you'),
                  subtitle: Text(
                    _type == QuestionType.codeAnswer
                        ? 'Students write code; you award the marks after the exam.'
                        : 'Students write an answer; you award the marks after the exam.',
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('question_save'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(widget.isEditing ? 'Save question' : 'Add question'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marksAndDifficulty() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: const Key('question_marks'),
            controller: _marks,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Marks',
              prefixIcon: Icon(Icons.star_outline),
            ),
            validator: (value) {
              final marks = int.tryParse((value ?? '').trim());
              if (marks == null) return 'Enter a number';
              if (marks < 1) return 'At least 1';
              if (marks > 100) return 'At most 100';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: const Key('question_difficulty'),
            initialValue: _difficulty,
            decoration: const InputDecoration(labelText: 'Difficulty'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Unset')),
              DropdownMenuItem(value: 'easy', child: Text('Easy')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'hard', child: Text('Hard')),
            ],
            onChanged: (value) => setState(() => _difficulty = value),
          ),
        ),
      ],
    );
  }

  Widget _codeSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              key: const Key('code_language'),
              initialValue: _language,
              decoration: const InputDecoration(labelText: 'Language'),
              items: [
                for (final language in codeLanguages)
                  DropdownMenuItem(value: language, child: Text(language.toUpperCase())),
              ],
              onChanged: (value) => setState(() => _language = value ?? 'cpp'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _timeLimit,
                    decoration: const InputDecoration(labelText: 'Time limit (s)'),
                    items: [
                      for (final seconds in [1, 2, 5, 10])
                        DropdownMenuItem(value: seconds, child: Text('$seconds')),
                    ],
                    onChanged: (value) => setState(() => _timeLimit = value ?? 2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _memoryLimit,
                    decoration: const InputDecoration(labelText: 'Memory (MB)'),
                    items: [
                      for (final megabytes in [64, 128, 256, 512])
                        DropdownMenuItem(value: megabytes, child: Text('$megabytes')),
                    ],
                    onChanged: (value) => setState(() => _memoryLimit = value ?? 256),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'These limits are recorded with the question and shown to students. Code is '
              'not executed by the platform; you mark it yourself.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionRow(int index) {
    final letter = String.fromCharCode(65 + index);
    final option = _options[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment:
            _optionsAreImages ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Radio<int>(key: Key('option_correct_$index'), value: index),
          Expanded(
            child: _optionsAreImages
                ? ImageField(
                    fieldKey: Key('option_image_$index'),
                    label: 'Option $letter',
                    url: option.imageUrl,
                    height: 120,
                    onChanged: (url) => setState(() {
                      option.imageUrl = url;
                      _error = null;
                    }),
                  )
                : TextFormField(
                    key: Key('option_text_$index'),
                    controller: option.text,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Option $letter',
                      isDense: true,
                    ),
                  ),
          ),
          IconButton(
            key: Key('option_remove_$index'),
            tooltip: _options.length <= minOptions
                ? 'A question needs at least $minOptions options'
                : 'Remove option',
            onPressed: _options.length <= minOptions ? null : () => _removeOption(index),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Route wrapper for adding a question: resolves the course from the exam so the caller
/// does not have to carry it through navigation.
class QuestionCreateScreen extends ConsumerWidget {
  const QuestionCreateScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examProvider(examId));
    return exam.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Add Question')),
        body: ErrorView(
          message: error is ApiException ? error.message : 'Could not load this exam.',
          onRetry: () => ref.invalidate(examProvider(examId)),
        ),
      ),
      data: (data) => QuestionBuilderScreen(examId: examId, courseId: data.courseId),
    );
  }
}

/// Route wrapper for editing a question: resolves both the exam and the question by id.
class QuestionEditScreen extends ConsumerWidget {
  const QuestionEditScreen({
    super.key,
    required this.examId,
    required this.examQuestionId,
  });

  final int examId;
  final int examQuestionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examProvider(examId));
    final questions = ref.watch(examQuestionsProvider(examId));

    if (exam.isLoading || questions.isLoading) {
      return const Scaffold(body: LoadingView());
    }

    final error = exam.error ?? questions.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Question')),
        body: ErrorView(
          message: error is ApiException ? error.message : 'Could not load this question.',
          onRetry: () => refreshExam(ref, examId),
        ),
      );
    }

    final existing =
        questions.requireValue.where((item) => item.id == examQuestionId).firstOrNull;
    if (existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Question')),
        body: const EmptyView(
          title: 'Question not found',
          subtitle: 'It may have been removed from this exam.',
          icon: Icons.help_outline,
        ),
      );
    }

    return QuestionBuilderScreen(
      examId: examId,
      courseId: exam.requireValue.courseId,
      existing: existing,
    );
  }
}
