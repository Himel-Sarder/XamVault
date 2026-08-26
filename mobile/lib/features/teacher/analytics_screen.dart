<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/analytics.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/config/semantic_colours.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/section.dart';
import 'package:uniexam/widgets/status_views.dart';

/// How an exam and its questions performed (§45, §46).
///
/// The charts are plain widgets rather than a charting package: these are two bar
/// charts, and a dependency would be more code to keep working than the bars are.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key, required this.examId});

  final int examId;

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  double _passPercentage = 40;

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(
      examAnalyticsProvider((examId: widget.examId, passPercentage: _passPercentage)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: analytics.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load analytics.',
          onRetry: () => ref.invalidate(examAnalyticsProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                title: Text(data.examTitle),
                subtitle: Text('${data.courseCode} · ${data.totalMarks} marks'),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              'Who sat it',
              Icons.groups_outlined,
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
                children: [
                  MetricTile(
                    label: 'Approved',
                    value: '${data.cohort.approved}',
                    icon: Icons.how_to_reg_outlined,
                    colour: context.status.info,
                  ),
                  MetricTile(
                    label: 'Submitted',
                    value: '${data.cohort.submitted}',
                    icon: Icons.task_alt,
                    colour: context.status.success,
                  ),
                  MetricTile(
                    label: 'In progress',
                    value: '${data.cohort.inProgress}',
                    icon: Icons.hourglass_bottom,
                    colour: context.status.warning,
                  ),
                  MetricTile(
                    label: 'Absent',
                    value: '${data.cohort.absent}',
                    icon: Icons.person_off_outlined,
                    // Not red: a student who did not sit an exam is a fact to record,
                    // not a failure to flag.
                    colour: context.status.neutral,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _scoresCard(data),
            const SizedBox(height: 16),
            _passCard(data),
            const SizedBox(height: 16),
            _distributionCard(data),
            const SizedBox(height: 16),
            _questionsCard(data),
          ],
        ),
      ),
    );
  }

  Widget _scoresCard(ExamAnalytics data) {
    final scores = data.scores;
    if (!scores.hasData) {
      return _section(
        'Scores',
        Icons.query_stats,
        // Not "0%" — that would read as "everyone failed" rather than "nobody sat it".
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Nobody has submitted this exam yet.'),
        ),
      );
    }
    // Each figure tinted by what it says about the cohort, so a low average is visible
    // before it is read. The threshold is the teacher's, not a hard-coded 50.
    return _section(
      'Scores',
      Icons.query_stats,
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          MetricTile(
            label: 'Average',
            value: '${scores.average!.toStringAsFixed(1)}%',
            icon: Icons.timeline,
            colour: scoreColour(context, scores.average!, pass: _passPercentage),
          ),
          MetricTile(
            label: 'Median',
            value: '${scores.median!.toStringAsFixed(1)}%',
            icon: Icons.horizontal_rule,
            colour: scoreColour(context, scores.median!, pass: _passPercentage),
          ),
          MetricTile(
            label: 'Highest',
            value: '${scores.highest!.toStringAsFixed(1)}%',
            icon: Icons.trending_up,
            colour: context.status.success,
          ),
          MetricTile(
            label: 'Lowest',
            value: '${scores.lowest!.toStringAsFixed(1)}%',
            icon: Icons.trending_down,
            colour: scoreColour(context, scores.lowest!, pass: _passPercentage),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, Widget child, {StatusColor? tint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, icon: icon, colour: tint),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: child)),
      ],
    );
  }

  Widget _passCard(ExamAnalytics data) {
    final theme = Theme.of(context);
    final total = data.passed + data.failed;

    return _section(
      'Pass rate',
      Icons.rule,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // The platform does not know a university's pass mark, so it states which
            // threshold these figures were computed at, and lets the teacher move it.
            'At or above ${_passPercentage.round()}%',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Slider(
            key: const Key('pass_threshold'),
            value: _passPercentage,
            max: 100,
            divisions: 20,
            label: '${_passPercentage.round()}%',
            onChanged: (value) => setState(() => _passPercentage = value),
          ),
          if (total == 0)
            const Text('No submissions to measure yet.')
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  if (data.passed > 0)
                    Expanded(
                      flex: data.passed,
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        color: context.status.success.container,
                        child: Text(
                          '${data.passed}',
                          style: TextStyle(
                              color: context.status.success.foreground,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (data.failed > 0)
                    Expanded(
                      flex: data.failed,
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        color: context.status.danger.container,
                        child: Text(
                          '${data.failed}',
                          style: TextStyle(
                              color: context.status.danger.foreground,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${data.passRate?.toStringAsFixed(1) ?? '—'}% at or above the threshold',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _distributionCard(ExamAnalytics data) {
    final theme = Theme.of(context);
    final peak = data.distribution.fold<int>(0, (a, b) => a > b.count ? a : b.count);

    return _section(
      'Score distribution',
      Icons.bar_chart,
      Column(
        children: [
          for (final bucket in data.distribution)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(bucket.label, style: theme.textTheme.bodySmall),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Container(
                            height: 20,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          Container(
                            height: 20,
                            width: peak == 0
                                ? 0
                                : constraints.maxWidth * (bucket.count / peak),
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${bucket.count}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _questionsCard(ExamAnalytics data) {
    final theme = Theme.of(context);
    return _section(
      'Question by question',
      Icons.checklist_rtl,
      Column(
        children: [
          for (final question in data.questions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Q${question.position}  ·  ${question.marks} marks',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    question.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  // Accuracy only means something for the choice types; written
                  // questions report what was actually awarded instead.
                  if (question.isAutoMarked)
                    _accuracyBar(question)
                  else
                    Text(
                      question.awaitingMarks > 0
                          ? '${question.awaitingMarks} still to mark'
                          : 'Average ${question.averageMarks?.toStringAsFixed(1) ?? '—'}'
                              ' of ${question.marks}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _accuracyBar(QuestionAnalytics question) {
    final theme = Theme.of(context);
    final correct = question.correct ?? 0;
    final wrong = question.wrong ?? 0;
    final skipped = question.skipped;
    final total = correct + wrong + skipped;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                if (correct > 0)
                  Expanded(
                    flex: correct,
                    child: Container(height: 12, color: theme.colorScheme.primary),
                  ),
                if (wrong > 0)
                  Expanded(
                    flex: wrong,
                    child: Container(height: 12, color: theme.colorScheme.error),
                  ),
                if (skipped > 0)
                  Expanded(
                    flex: skipped,
                    child: Container(
                      height: 12,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Correct $correct · Wrong $wrong · Skipped $skipped'
          '${question.correctRate != null ? '  (${question.correctRate!.toStringAsFixed(0)}%)' : ''}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
=======
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/analytics.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/config/semantic_colours.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/section.dart';
import 'package:uniexam/widgets/status_views.dart';

/// How an exam and its questions performed (§45, §46).
///
/// The charts are plain widgets rather than a charting package: these are two bar
/// charts, and a dependency would be more code to keep working than the bars are.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key, required this.examId});

  final int examId;

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  double _passPercentage = 40;

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(
      examAnalyticsProvider((examId: widget.examId, passPercentage: _passPercentage)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: analytics.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load analytics.',
          onRetry: () => ref.invalidate(examAnalyticsProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                title: Text(data.examTitle),
                subtitle: Text('${data.courseCode} · ${data.totalMarks} marks'),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              'Who sat it',
              Icons.groups_outlined,
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
                children: [
                  MetricTile(
                    label: 'Approved',
                    value: '${data.cohort.approved}',
                    icon: Icons.how_to_reg_outlined,
                    colour: context.status.info,
                  ),
                  MetricTile(
                    label: 'Submitted',
                    value: '${data.cohort.submitted}',
                    icon: Icons.task_alt,
                    colour: context.status.success,
                  ),
                  MetricTile(
                    label: 'In progress',
                    value: '${data.cohort.inProgress}',
                    icon: Icons.hourglass_bottom,
                    colour: context.status.warning,
                  ),
                  MetricTile(
                    label: 'Absent',
                    value: '${data.cohort.absent}',
                    icon: Icons.person_off_outlined,
                    // Not red: a student who did not sit an exam is a fact to record,
                    // not a failure to flag.
                    colour: context.status.neutral,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _scoresCard(data),
            const SizedBox(height: 16),
            _passCard(data),
            const SizedBox(height: 16),
            _distributionCard(data),
            const SizedBox(height: 16),
            _questionsCard(data),
          ],
        ),
      ),
    );
  }

  Widget _scoresCard(ExamAnalytics data) {
    final scores = data.scores;
    if (!scores.hasData) {
      return _section(
        'Scores',
        Icons.query_stats,
        // Not "0%" — that would read as "everyone failed" rather than "nobody sat it".
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Nobody has submitted this exam yet.'),
        ),
      );
    }
    // Each figure tinted by what it says about the cohort, so a low average is visible
    // before it is read. The threshold is the teacher's, not a hard-coded 50.
    return _section(
      'Scores',
      Icons.query_stats,
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          MetricTile(
            label: 'Average',
            value: '${scores.average!.toStringAsFixed(1)}%',
            icon: Icons.timeline,
            colour: scoreColour(context, scores.average!, pass: _passPercentage),
          ),
          MetricTile(
            label: 'Median',
            value: '${scores.median!.toStringAsFixed(1)}%',
            icon: Icons.horizontal_rule,
            colour: scoreColour(context, scores.median!, pass: _passPercentage),
          ),
          MetricTile(
            label: 'Highest',
            value: '${scores.highest!.toStringAsFixed(1)}%',
            icon: Icons.trending_up,
            colour: context.status.success,
          ),
          MetricTile(
            label: 'Lowest',
            value: '${scores.lowest!.toStringAsFixed(1)}%',
            icon: Icons.trending_down,
            colour: scoreColour(context, scores.lowest!, pass: _passPercentage),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, Widget child, {StatusColor? tint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, icon: icon, colour: tint),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: child)),
      ],
    );
  }

  Widget _passCard(ExamAnalytics data) {
    final theme = Theme.of(context);
    final total = data.passed + data.failed;

    return _section(
      'Pass rate',
      Icons.rule,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // The platform does not know a university's pass mark, so it states which
            // threshold these figures were computed at, and lets the teacher move it.
            'At or above ${_passPercentage.round()}%',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Slider(
            key: const Key('pass_threshold'),
            value: _passPercentage,
            max: 100,
            divisions: 20,
            label: '${_passPercentage.round()}%',
            onChanged: (value) => setState(() => _passPercentage = value),
          ),
          if (total == 0)
            const Text('No submissions to measure yet.')
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  if (data.passed > 0)
                    Expanded(
                      flex: data.passed,
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        color: context.status.success.container,
                        child: Text(
                          '${data.passed}',
                          style: TextStyle(
                              color: context.status.success.foreground,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (data.failed > 0)
                    Expanded(
                      flex: data.failed,
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        color: context.status.danger.container,
                        child: Text(
                          '${data.failed}',
                          style: TextStyle(
                              color: context.status.danger.foreground,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${data.passRate?.toStringAsFixed(1) ?? '—'}% at or above the threshold',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _distributionCard(ExamAnalytics data) {
    final theme = Theme.of(context);
    final peak = data.distribution.fold<int>(0, (a, b) => a > b.count ? a : b.count);

    return _section(
      'Score distribution',
      Icons.bar_chart,
      Column(
        children: [
          for (final bucket in data.distribution)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(bucket.label, style: theme.textTheme.bodySmall),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Container(
                            height: 20,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          Container(
                            height: 20,
                            width: peak == 0
                                ? 0
                                : constraints.maxWidth * (bucket.count / peak),
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${bucket.count}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _questionsCard(ExamAnalytics data) {
    final theme = Theme.of(context);
    return _section(
      'Question by question',
      Icons.checklist_rtl,
      Column(
        children: [
          for (final question in data.questions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Q${question.position}  ·  ${question.marks} marks',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    question.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  // Accuracy only means something for the choice types; written
                  // questions report what was actually awarded instead.
                  if (question.isAutoMarked)
                    _accuracyBar(question)
                  else
                    Text(
                      question.awaitingMarks > 0
                          ? '${question.awaitingMarks} still to mark'
                          : 'Average ${question.averageMarks?.toStringAsFixed(1) ?? '—'}'
                              ' of ${question.marks}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _accuracyBar(QuestionAnalytics question) {
    final theme = Theme.of(context);
    final correct = question.correct ?? 0;
    final wrong = question.wrong ?? 0;
    final skipped = question.skipped;
    final total = correct + wrong + skipped;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                if (correct > 0)
                  Expanded(
                    flex: correct,
                    child: Container(height: 12, color: theme.colorScheme.primary),
                  ),
                if (wrong > 0)
                  Expanded(
                    flex: wrong,
                    child: Container(height: 12, color: theme.colorScheme.error),
                  ),
                if (skipped > 0)
                  Expanded(
                    flex: skipped,
                    child: Container(
                      height: 12,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Correct $correct · Wrong $wrong · Skipped $skipped'
          '${question.correctRate != null ? '  (${question.correctRate!.toStringAsFixed(0)}%)' : ''}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
