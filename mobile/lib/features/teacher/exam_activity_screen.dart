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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _Headline(data: data),
                const SizedBox(height: 16),
                _Counts(data: data),
                const SizedBox(height: 24),
                SectionHeader(
                  title: 'Per student',
                  icon: Icons.people_outline,
                  subtitle: 'Most activity first · tap for the full trail',
                ),
                for (final student in data.students)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StudentCard(summary: student),
                  ),
                const SizedBox(height: 8),
                const _Footnote(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The one-line answer, before any numbers.
///
/// A teacher opening this wants to know whether anything needs their attention. Making
/// them assemble that from three separate figures is work the screen can do for them.
class _Headline extends StatelessWidget {
  const _Headline({required this.data});

  final ExamSecuritySummary data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = data.totalExits == 0 && data.unprotected == 0;
    final tint = quiet ? context.status.success : context.status.warning;

    final headline = quiet
        ? 'Nothing unusual recorded'
        : '${data.studentsWhoLeft} of ${data.students.length} '
            '${data.students.length == 1 ? 'student' : 'students'} left the app';
    final detail = quiet
        ? 'Every student stayed in the app, on a device that reported protection.'
        : 'Leaving has ordinary explanations. The trail is here so a person can judge, '
            'not so the app can.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tint.container,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.foreground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              quiet ? Icons.verified_user_outlined : Icons.visibility_outlined,
              size: 22,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tint.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(color: tint.foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Three figures, laid out so none of them is ellipsised on a phone.
///
/// They were a Row of equal thirds, which at phone width cut "Students who left" and
/// "Unprotected" mid-word. A wrap of self-sizing cards keeps every label readable at any
/// width instead of dividing the screen and hoping.
class _Counts extends StatelessWidget {
  const _Counts({required this.data});

  final ExamSecuritySummary data;

  @override
  Widget build(BuildContext context) {
    final entries = <({String label, String value, IconData icon, StatusColor colour})>[
      (
        label: 'Left the app',
        value: '${data.studentsWhoLeft}/${data.students.length}',
        icon: Icons.logout,
        colour:
            data.studentsWhoLeft == 0 ? context.status.success : context.status.warning,
      ),
      (
        label: 'Exits in total',
        value: '${data.totalExits}',
        icon: Icons.open_in_new,
        colour: data.totalExits == 0 ? context.status.success : context.status.warning,
      ),
      (
        label: 'Ran unprotected',
        value: '${data.unprotected}',
        icon: Icons.gpp_bad_outlined,
        colour: data.unprotected == 0 ? context.status.success : context.status.danger,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two across on a phone, three on anything wider. Never one third of 360px.
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in entries)
              SizedBox(
                width: width,
                child: _CountCard(
                  label: entry.label,
                  value: entry.value,
                  icon: entry.icon,
                  colour: entry.colour,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.colour,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusColor colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.container,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colour.foreground),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colour.foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          // Wraps rather than ellipsising: a label a reader cannot finish is worse
          // than one that takes two lines.
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colour.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
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

String _duration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

class _StudentCard extends ConsumerStatefulWidget {
  const _StudentCard({required this.summary});

  final StudentSecuritySummary summary;

  @override
  ConsumerState<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends ConsumerState<_StudentCard> {
  bool _expanded = false;

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
          // A stripe rather than a tinted card, so the colour reads at a glance without
          // washing the name beside it.
          Container(height: 4, color: tint.foreground),
          InkWell(
            key: Key('activity_${s.attemptId}'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint.container,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${s.exits}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: tint.foreground,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        Text(
                          s.exits == 1 ? 'exit' : 'exits',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tint.foreground,
                            fontSize: 9,
                            height: 1.4,
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
                          s.studentName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.studentNumber ?? 'ID unavailable',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.exits == 0
                              ? 'Stayed in the app throughout'
                              : '${_duration(s.secondsAway)} away'
                                  '${s.unreturnedExits > 0 ? ' · did not return' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tint.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
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
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.exits > 0)
                StatusPill(
                  label: 'Longest ${_duration(s.longestAwaySeconds)}',
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: s.ranUnprotected
                    ? context.status.danger.container
                    : context.status.success.container,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    s.ranUnprotected
                        ? Icons.gpp_bad_outlined
                        : Icons.gpp_good_outlined,
                    size: 16,
                    color: s.ranUnprotected
                        ? context.status.danger.foreground
                        : context.status.success.foreground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.lockdown!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: s.ranUnprotected
                            ? context.status.danger.foreground
                            : context.status.success.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'What the device reported',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
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
    'DEVELOPER_MODE': 'Developer options on',
    'USB_DEBUGGING': 'USB debugging on',
    'SPLIT_SCREEN': 'Split screen',
    'EXTERNAL_DISPLAY': 'Second display attached',
    'OVERLAY_DETECTED': 'Something drawn over the exam',
  };

  static StatusColor _tint(BuildContext context, String severity) => switch (severity) {
        'critical' => context.status.danger,
        'warning' => context.status.warning,
        _ => context.status.neutral,
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
                padding: const EdgeInsets.only(bottom: 10),
                // A stacked row rather than fixed-width columns: a 132px timestamp
                // column left the label a sliver on a phone, and cut it.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        color: _tint(context, event.severity).foreground,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  // An unrecognised type is shown verbatim rather than
                                  // dropped: a server that learns a new event must not
                                  // make this screen go silent.
                                  _labels[event.eventType] ?? event.eventType,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (event.awaySeconds != null)
                                StatusPill(
                                  label: 'away ${_duration(event.awaySeconds!)}',
                                  colour: context.status.warning,
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatDateTime(event.occurredAt),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
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
