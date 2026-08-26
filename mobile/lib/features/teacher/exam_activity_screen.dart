import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/security_summary.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/widgets/section.dart';
import 'package:uniexam/widgets/status_pill.dart';
import 'package:uniexam/widgets/status_views.dart';

/// What each student's device reported while they sat the exam.
///
/// This screen deliberately never says "cheating". Every line on it has an innocent
/// explanation as well as a suspicious one — a call arrives, a sibling walks in, the
/// network drops, a phone dies — so it counts, orders by how unusual, and stops there.
/// Deciding what any of it means is the invigilator's job, and the wording is chosen so
/// the screen cannot be mistaken for having made that decision already (§38).
class ExamActivityScreen extends ConsumerWidget {
  const ExamActivityScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(examActivityProvider(examId));

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Activity')),
      body: summary.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load the activity.',
          onRetry: () => ref.invalidate(examActivityProvider(examId)),
        ),
        data: (data) {
          if (data.students.isEmpty) {
            return const EmptyView(
              title: 'Nobody has sat this exam yet',
              subtitle: 'Once students start, what their devices report appears here.',
              icon: Icons.shield_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(examActivityProvider(examId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _overview(context, data),
                const SizedBox(height: 20),
                SectionHeader(
                  title: 'Per student',
                  icon: Icons.people_outline,
                  subtitle: 'Most activity first',
                ),
                for (final student in data.students)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _StudentCard(summary: student),
                  ),
                const SizedBox(height: 16),
                _footnote(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _overview(BuildContext context, ExamSecuritySummary data) {
    return Row(
      children: [
        Expanded(
          child: MetricTile(
            label: 'Students who left',
            value: '${data.studentsWhoLeft}',
            icon: Icons.logout,
            colour: data.studentsWhoLeft == 0
                ? context.status.success
                : context.status.warning,
            caption: 'of ${data.students.length}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricTile(
            label: 'Total exits',
            value: '${data.totalExits}',
            icon: Icons.open_in_new,
            colour:
                data.totalExits == 0 ? context.status.success : context.status.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricTile(
            label: 'Unprotected',
            value: '${data.unprotected}',
            icon: Icons.no_encryption_gmailerrorred_outlined,
            // Devices that granted no lockdown. Context for every other number here.
            colour:
                data.unprotected == 0 ? context.status.success : context.status.danger,
          ),
        ),
      ],
    );
  }

  Widget _footnote(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is a record of what each device reported, not a finding. A call, a '
              'notification, a dropped connection or a flat battery all appear here the '
              'same way a deliberate exit does.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends ConsumerStatefulWidget {
  const _StudentCard({required this.summary});

  final StudentSecuritySummary summary;

  @override
  ConsumerState<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends ConsumerState<_StudentCard> {
  bool _expanded = false;

  static String _duration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes < 60) return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.summary;

    // Ordered by how much a human needs to look, not by severity of accusation.
    final tint = s.critical > 0
        ? context.status.danger
        : (s.exits > 0 || s.warnings > 0
            ? context.status.warning
            : context.status.success);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            key: Key('activity_${s.attemptId}'),
            onTap: () => setState(() => _expanded = !_expanded),
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.container,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${s.exits}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: tint.foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(s.studentName),
            subtitle: Text(
              s.exits == 0
                  ? 'Stayed in the app throughout'
                  : '${s.exits} exit${s.exits == 1 ? '' : 's'} · '
                      '${_duration(s.secondsAway)} away'
                      '${s.unreturnedExits > 0 ? ' · did not return' : ''}',
            ),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          ),
          if (_expanded) _detail(context, s),
        ],
      ),
    );
  }

  Widget _detail(BuildContext context, StudentSecuritySummary s) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 20),
          if (s.studentNumber != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                s.studentNumber!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.exits > 0)
                StatusPill(
                  label: 'Longest away ${_duration(s.longestAwaySeconds)}',
                  colour: context.status.warning,
                ),
              if (s.unreturnedExits > 0)
                StatusPill(
                  // Counted apart because it carries no duration: an exit with no
                  // return would otherwise read as no time away at all.
                  label: '${s.unreturnedExits} never returned',
                  colour: context.status.danger,
                ),
              if (s.screenshotAttempts > 0)
                StatusPill(
                  label: '${s.screenshotAttempts} screenshot',
                  colour: context.status.danger,
                ),
              if (s.screenRecordings > 0)
                StatusPill(
                  label: '${s.screenRecordings} recording',
                  colour: context.status.danger,
                ),
              if (s.timeChanges > 0)
                StatusPill(
                  label: '${s.timeChanges} clock change',
                  colour: context.status.warning,
                ),
              if (s.restarts > 0)
                StatusPill(
                  label: '${s.restarts} restart',
                  colour: context.status.warning,
                ),
              if (s.isQuiet)
                StatusPill(label: 'Nothing recorded', colour: context.status.success),
            ],
          ),
          if (s.lockdown != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  s.ranUnprotected ? Icons.gpp_bad_outlined : Icons.gpp_good_outlined,
                  size: 16,
                  color: s.ranUnprotected
                      ? context.status.danger.foreground
                      : context.status.success.foreground,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.lockdown!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: s.ranUnprotected
                          ? context.status.danger.foreground
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _Trail(attemptId: s.attemptId),
        ],
      ),
    );
  }
}

/// The event-by-event record behind one row, loaded only when opened.
class _Trail extends ConsumerWidget {
  const _Trail({required this.attemptId});

  final int attemptId;

  static const _labels = {
    'APP_BACKGROUND': 'Left the app',
    'APP_FOREGROUND': 'Came back',
    'SCREENSHOT_ATTEMPT': 'Screenshot attempt',
    'SCREEN_RECORDING': 'Screen recording',
    'EXTERNAL_ACTIVITY': 'Another app',
    'NETWORK_DISCONNECT': 'Lost connection',
    'NETWORK_RECONNECT': 'Reconnected',
    'DEVICE_TIME_CHANGE': 'Device clock changed',
    'EXAM_RESTART': 'Resumed the exam',
    'LOCKDOWN_ENGAGED': 'Lockdown engaged',
    'LOCKDOWN_UNAVAILABLE': 'Lockdown unavailable',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trail = ref.watch(attemptActivityProvider(attemptId));

    return trail.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => Text(
        'Could not load the detail.',
        style: theme.textTheme.bodySmall,
      ),
      data: (report) {
        if (report.events.isEmpty) {
          return Text(
            'The device reported nothing during this attempt.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final event in report.events)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 132,
                      child: Text(
                        formatDateTime(event.occurredAt),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        // An unrecognised type is shown verbatim rather than dropped:
                        // a server that learns a new event must not go silent here.
                        _labels[event.eventType] ?? event.eventType,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (event.awaySeconds != null)
                      Text(
                        'away ${_StudentCardState._duration(event.awaySeconds!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.status.warning.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
