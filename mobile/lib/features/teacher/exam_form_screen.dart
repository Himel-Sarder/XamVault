import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/providers/exam_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Create a new exam, or edit a draft.
///
/// Only drafts reach the edit path — a published exam is frozen server-side, and the
/// detail screen does not offer the button.
class ExamFormScreen extends ConsumerStatefulWidget {
  const ExamFormScreen({super.key, required this.courseId, this.exam});

  final int courseId;
  final Exam? exam;

  bool get isEditing => exam != null;

  @override
  ConsumerState<ExamFormScreen> createState() => _ExamFormScreenState();
}

class _ExamFormScreenState extends ConsumerState<ExamFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _duration;

  DateTime? _startAt;
  late ExamSettings _settings;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final exam = widget.exam;
    _title = TextEditingController(text: exam?.title ?? '');
    _description = TextEditingController(text: exam?.description ?? '');
    _duration = TextEditingController(text: '${exam?.durationMinutes ?? 30}');
    _startAt = exam?.startAt;
    _settings = exam?.settings ?? const ExamSettings();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startAt ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt ?? now),
    );
    if (time == null) return;

    setState(() {
      _startAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final repository = ref.read(examRepositoryProvider);
    final duration = int.parse(_duration.text.trim());

    try {
      final Exam saved;
      if (widget.isEditing) {
        saved = await repository.update(
          widget.exam!.id,
          title: _title.text.trim(),
          description: _description.text.trim(),
          startAt: _startAt,
          durationMinutes: duration,
        );
        await repository.updateSettings(saved.id, _settings);
      } else {
        saved = await repository.create(
          courseId: widget.courseId,
          title: _title.text.trim(),
          description: _description.text.trim(),
          startAt: _startAt,
          durationMinutes: duration,
          settings: _settings,
        );
      }
      refreshExam(ref, saved.id, courseId: widget.courseId);
      if (mounted) context.pop(saved.id);
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
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit Exam' : 'Create Exam')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextFormField(
              key: const Key('exam_title'),
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Exam title',
                hintText: 'e.g. Mid Term Quiz',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Give the exam a title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('exam_description'),
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What this exam covers',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            Text('Schedule', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                key: const Key('exam_start_at'),
                leading: const Icon(Icons.event_outlined),
                title: const Text('Starts'),
                subtitle: Text(formatDateTime(_startAt, ifNull: 'Tap to choose')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickStart,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('exam_duration'),
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              validator: (value) {
                final minutes = int.tryParse((value ?? '').trim());
                if (minutes == null) return 'Enter a number of minutes';
                if (minutes < 1) return 'Duration must be at least 1 minute';
                if (minutes > 24 * 60) return 'Duration cannot exceed 24 hours';
                return null;
              },
            ),
            const SizedBox(height: 24),
            Text('Exam settings', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _settingsCard(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('exam_save'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(widget.isEditing ? 'Save changes' : 'Create exam'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard() {
    return Card(
      child: Column(
        children: [
          _toggle(
            key: const Key('setting_shuffle_questions'),
            title: 'Shuffle questions',
            subtitle: 'Each student gets their own question order',
            value: _settings.shuffleQuestions,
            onChanged: (value) =>
                setState(() => _settings = _settings.copyWith(shuffleQuestions: value)),
          ),
          _toggle(
            title: 'Shuffle answers',
            subtitle: 'Each student gets their own option order',
            value: _settings.shuffleAnswers,
            onChanged: (value) =>
                setState(() => _settings = _settings.copyWith(shuffleAnswers: value)),
          ),
          _toggle(
            title: 'Allow going back',
            subtitle: 'Students can return to earlier questions',
            value: _settings.allowBackNavigation,
            onChanged: (value) => setState(
                () => _settings = _settings.copyWith(allowBackNavigation: value)),
          ),
          _toggle(
            title: 'Auto submit',
            subtitle: 'Submit automatically when the time runs out',
            value: _settings.autoSubmit,
            onChanged: (value) =>
                setState(() => _settings = _settings.copyWith(autoSubmit: value)),
          ),
          _toggle(
            key: const Key('setting_secure_mode'),
            title: 'Secure mode',
            subtitle: 'Lock the device down during the exam (Android)',
            value: _settings.secureMode,
            onChanged: (value) =>
                setState(() => _settings = _settings.copyWith(secureMode: value)),
          ),
          _toggle(
            title: 'Show result immediately',
            subtitle: 'Reveal the score as soon as the exam is submitted',
            value: _settings.showResultImmediately,
            onChanged: (value) => setState(
                () => _settings = _settings.copyWith(showResultImmediately: value)),
          ),
          ListTile(
            title: const Text('Maximum attempts'),
            trailing: DropdownButton<int>(
              key: const Key('setting_max_attempts'),
              value: _settings.maxAttempts,
              onChanged: (value) =>
                  setState(() => _settings = _settings.copyWith(maxAttempts: value)),
              items: [
                for (var n = 1; n <= 5; n++)
                  DropdownMenuItem(value: n, child: Text('$n')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Key? key,
  }) {
    return SwitchListTile(
      key: key,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Route wrapper for editing: resolves the exam from its id.
///
/// Passing the object through GoRouter's `extra` would be lighter, but `extra` is lost on
/// a deep link or a browser refresh, and the form would then open against a null exam.
class ExamEditScreen extends ConsumerWidget {
  const ExamEditScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examProvider(examId));
    return exam.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit Exam')),
        body: ErrorView(
          message: error is ApiException ? error.message : 'Could not load this exam.',
          onRetry: () => ref.invalidate(examProvider(examId)),
        ),
      ),
      data: (data) => ExamFormScreen(courseId: data.courseId, exam: data),
    );
  }
}
