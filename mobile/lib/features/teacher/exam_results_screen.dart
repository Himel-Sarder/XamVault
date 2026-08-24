import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/file_download.dart';
import 'package:uniexam/models/exam_result.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Marks for one exam, and the button that releases them to students.
class ExamResultsScreen extends ConsumerStatefulWidget {
  const ExamResultsScreen({super.key, required this.examId});

  final int examId;

  @override
  ConsumerState<ExamResultsScreen> createState() => _ExamResultsScreenState();
}

class _ExamResultsScreenState extends ConsumerState<ExamResultsScreen> {
  bool _publishing = false;
  String? _exporting;

  /// Fetches the report with the caller's token, then hands the bytes to the platform.
  Future<void> _export(String kind) async {
    setState(() => _exporting = kind);
    try {
      final repository = ref.read(examRepositoryProvider);
      final file = kind == 'pdf'
          ? await repository.examPdf(widget.examId)
          : await repository.examExcel(widget.examId);
      await saveFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: kind == 'pdf'
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } on ApiException catch (error) {
      _tell(error.message);
    } on UnsupportedError catch (error) {
      // Said plainly rather than failing silently on a platform that cannot save yet.
      _tell(error.message ?? 'Saving files is not available on this platform yet');
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _publish(List<TeacherResult> pending) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Release these marks?'),
        content: Text(
          '${pending.length} result${pending.length == 1 ? '' : 's'} will become visible '
          'to the students they belong to.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Release'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _publishing = true);
    try {
      await ref.read(examRepositoryProvider).publishResults(widget.examId);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _publishing = false);
        ref.invalidate(examResultsProvider(widget.examId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(examResultsProvider(widget.examId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          IconButton(
            key: const Key('export_pdf'),
            tooltip: 'Export PDF',
            onPressed: _exporting != null ? null : () => _export('pdf'),
            icon: _exporting == 'pdf'
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            key: const Key('export_excel'),
            tooltip: 'Export Excel',
            onPressed: _exporting != null ? null : () => _export('excel'),
            icon: _exporting == 'excel'
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_chart_outlined),
          ),
        ],
      ),
      body: results.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load the results.',
          onRetry: () => ref.invalidate(examResultsProvider(widget.examId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No submissions yet',
              subtitle: 'Results appear here as students submit the exam.',
              icon: Icons.emoji_events_outlined,
            );
          }
          final pending = items.where((result) => !result.isPublished).toList();
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(examResultsProvider(widget.examId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(items),
                const SizedBox(height: 16),
                if (pending.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('publish_results'),
                        onPressed: _publishing ? null : () => _publish(pending),
                        icon: _publishing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Icon(Icons.campaign_outlined),
                        label: Text('Release ${pending.length} result'
                            '${pending.length == 1 ? '' : 's'} to students'),
                      ),
                    ),
                  ),
                for (final result in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _resultTile(result),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summary(List<TeacherResult> items) {
    final theme = Theme.of(context);
    final scores = items.map((result) => result.percentage).toList()..sort();
    final average = scores.reduce((a, b) => a + b) / scores.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat(theme, 'Submitted', '${items.length}'),
            _stat(theme, 'Average', '${average.toStringAsFixed(1)}%'),
            _stat(theme, 'Highest', '${scores.last.toStringAsFixed(1)}%'),
            _stat(theme, 'Lowest', '${scores.first.toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String label, String value) {
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _resultTile(TeacherResult result) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Text(
            '${result.percentage.round()}',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
          ),
        ),
        title: Text(result.studentName),
        subtitle: Text(
          '${result.studentNumber} · '
          '${result.totalScore.toStringAsFixed(result.totalScore % 1 == 0 ? 0 : 2)}'
          '/${result.totalMarks}',
        ),
        trailing: result.isPublished
            ? Icon(Icons.visibility_outlined, color: theme.colorScheme.primary)
            : Icon(Icons.visibility_off_outlined, color: theme.colorScheme.outline),
      ),
    );
  }
}
