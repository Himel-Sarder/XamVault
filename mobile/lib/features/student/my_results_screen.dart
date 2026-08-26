<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/file_download.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/exam_result.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/config/semantic_colours.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/section.dart';
import 'package:uniexam/widgets/status_views.dart';

/// A student's released marks. Unreleased results are not returned by the API at all,
/// so there is nothing here to filter.
class MyResultsScreen extends ConsumerWidget {
  const MyResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(myResultsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Results')),
      body: results.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load your results.',
          onRetry: () => ref.invalidate(myResultsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No results yet',
              subtitle: 'Results appear here once your teacher releases the marks.',
              icon: Icons.emoji_events_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(myResultsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _ResultCard(result: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ResultCard extends ConsumerStatefulWidget {
  const _ResultCard({required this.result});

  final ExamResult result;

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  bool _exporting = false;

  ExamResult get result => widget.result;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await ref.read(studentRepositoryProvider).resultPdf(result.id);
      await saveFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: 'application/pdf',
      );
    } on ApiException catch (error) {
      _tell(error.message);
    } on UnsupportedError catch (error) {
      _tell(error.message ?? 'Saving files is not available on this platform yet');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A band, not a verdict: the passing mark is a policy the university sets and this
    // app is never told it, so the colour grades by achievement and never reaches red.
    final tone = achievementColour(context, result.percentage);
    final fraction =
        result.totalMarks == 0 ? 0.0 : result.totalScore / result.totalMarks;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The score is the reason this card exists, so it is the biggest thing
                // on it rather than a number in the corner.
                Container(
                  width: 78,
                  height: 78,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.container,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // The exact figure, not a rounded one: a student comparing
                      // 79.5% with 80.0% is entitled to see the difference.
                      Text(
                        '${result.percentage.toStringAsFixed(1)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tone.foreground,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.courseCode,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.accents.forKey(result.courseCode).foreground,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(result.examTitle, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      MeterBar(fraction: fraction, colour: tone),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${result.totalScore.toStringAsFixed(result.totalScore % 1 == 0 ? 0 : 2)}'
              ' out of ${result.totalMarks} marks',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Submitted ${formatDateTime(result.submittedAt)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  key: Key('download_result_${result.id}'),
                  onPressed: _exporting ? null : _export,
                  icon: _exporting
                      ? const SizedBox(
                          height: 14, width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
=======
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/file_download.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/exam_result.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/config/semantic_colours.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/section.dart';
import 'package:uniexam/widgets/status_views.dart';

/// A student's released marks. Unreleased results are not returned by the API at all,
/// so there is nothing here to filter.
class MyResultsScreen extends ConsumerWidget {
  const MyResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(myResultsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Results')),
      body: results.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load your results.',
          onRetry: () => ref.invalidate(myResultsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No results yet',
              subtitle: 'Results appear here once your teacher releases the marks.',
              icon: Icons.emoji_events_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(myResultsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _ResultCard(result: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ResultCard extends ConsumerStatefulWidget {
  const _ResultCard({required this.result});

  final ExamResult result;

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  bool _exporting = false;

  ExamResult get result => widget.result;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await ref.read(studentRepositoryProvider).resultPdf(result.id);
      await saveFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: 'application/pdf',
      );
    } on ApiException catch (error) {
      _tell(error.message);
    } on UnsupportedError catch (error) {
      _tell(error.message ?? 'Saving files is not available on this platform yet');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A band, not a verdict: the passing mark is a policy the university sets and this
    // app is never told it, so the colour grades by achievement and never reaches red.
    final tone = achievementColour(context, result.percentage);
    final fraction =
        result.totalMarks == 0 ? 0.0 : result.totalScore / result.totalMarks;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The score is the reason this card exists, so it is the biggest thing
                // on it rather than a number in the corner.
                Container(
                  width: 78,
                  height: 78,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.container,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // The exact figure, not a rounded one: a student comparing
                      // 79.5% with 80.0% is entitled to see the difference.
                      Text(
                        '${result.percentage.toStringAsFixed(1)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tone.foreground,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.courseCode,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.accents.forKey(result.courseCode).foreground,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(result.examTitle, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      MeterBar(fraction: fraction, colour: tone),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${result.totalScore.toStringAsFixed(result.totalScore % 1 == 0 ? 0 : 2)}'
              ' out of ${result.totalMarks} marks',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Submitted ${formatDateTime(result.submittedAt)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  key: Key('download_result_${result.id}'),
                  onPressed: _exporting ? null : _export,
                  icon: _exporting
                      ? const SizedBox(
                          height: 14, width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
