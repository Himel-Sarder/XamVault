import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/student/widgets/student_exam_tile.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/student_exam.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/providers/student_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

/// One exam, and the button that asks the teacher for admission.
class StudentExamDetailScreen extends ConsumerWidget {
  const StudentExamDetailScreen({super.key, required this.examId});

  final int examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(studentExamProvider(examId));

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Details')),
      body: exam.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this exam.',
          onRetry: () => ref.invalidate(studentExamProvider(examId)),
        ),
        data: (data) => _Body(exam: data),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.exam});

  final StudentExam exam;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _requesting = false;
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      // The server decides whether this is a new sitting or a resume, and owns the
      // clock either way.
      final attempt = await ref.read(studentRepositoryProvider).startExam(widget.exam.id);
      if (mounted) context.push(Routes.studentAttempt(attempt.id));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
      refreshStudentExam(ref, widget.exam.id);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    try {
      await ref.read(studentRepositoryProvider).requestToJoin(widget.exam.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent to your teacher')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      // Re-read either way: a refusal usually means the server knows something this
      // screen did not, and the fresh state is what should be shown.
      if (mounted) {
        setState(() => _requesting = false);
        refreshStudentExam(ref, widget.exam.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exam = widget.exam;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(exam.courseCode, style: theme.textTheme.labelLarge),
                    ),
                    AvailabilityChip(availability: exam.availability),
                  ],
                ),
                const SizedBox(height: 4),
                Text(exam.courseName, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Text(exam.title, style: theme.textTheme.titleLarge),
                if (exam.description != null && exam.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(exam.description!, style: theme.textTheme.bodyMedium),
                ],
                const Divider(height: 24),
                _row(Icons.event_outlined, 'Starts',
                    formatDateTime(exam.startAt, ifNull: 'Not set')),
                _row(Icons.timer_outlined, 'Duration', '${exam.durationMinutes} minutes'),
                _row(Icons.help_outline, 'Questions', '${exam.questionCount}'),
                _row(Icons.star_outline, 'Total marks', '${exam.totalMarks}'),
                _row(Icons.repeat, 'Attempts allowed', '${exam.settings.maxAttempts}'),
              ],
            ),
          ),
        ),
        if (exam.settings.secureMode) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
              title: const Text('Secure mode'),
              subtitle: const Text(
                'Your device will be locked to the exam while it is running, and '
                'leaving the app is recorded.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _JoinSection(
          exam: exam,
          requesting: _requesting,
          onRequest: _request,
          starting: _starting,
          onStart: _start,
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
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

/// The one place a student acts on an exam.
///
/// What it offers is driven entirely by `canRequestJoin` and the request status, both
/// computed by the server — the app never decides eligibility for itself.
class _JoinSection extends StatelessWidget {
  const _JoinSection({
    required this.exam,
    required this.requesting,
    required this.onRequest,
    required this.starting,
    required this.onStart,
  });

  final StudentExam exam;
  final bool requesting;
  final VoidCallback onRequest;
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, title, body) = switch (exam.joinRequestStatus) {
      JoinRequestStatus.pending => (
          Icons.hourglass_top_outlined,
          'Waiting for approval',
          'Your teacher has your request. You can start once it is approved.',
        ),
      JoinRequestStatus.approved => (
          Icons.verified_outlined,
          'You are approved',
          'Come back when the exam opens to start it.',
        ),
      JoinRequestStatus.rejected => (
          Icons.cancel_outlined,
          'Request not approved',
          'Speak to your teacher. You can send another request.',
        ),
      JoinRequestStatus.none => (
          Icons.how_to_reg_outlined,
          'Not requested yet',
          'Ask your teacher to admit you to this exam.',
        ),
    };

    // Starting is offered only when the server says the student is approved *and* the
    // window is open. It re-checks all of §32 anyway; this just avoids a pointless tap.
    final canStart = exam.isApproved && exam.availability == ExamAvailability.open;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: Icon(icon, color: theme.colorScheme.primary),
            title: Text(canStart ? 'Ready to start' : title),
            subtitle: Text(
              canStart
                  ? 'Once you start, the timer runs on the server and cannot be paused.'
                  : body,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canStart)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('start_exam'),
              onPressed: onStart,
              icon: starting
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.play_arrow),
              label: const Text('Start exam'),
            ),
          )
        else if (exam.isApproved && exam.availability == ExamAvailability.upcoming)
          Text(
            'You can start when the exam opens.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          )
        else if (exam.canRequestJoin)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('request_to_join'),
              onPressed: requesting ? null : onRequest,
              icon: requesting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.how_to_reg_outlined),
              label: const Text('Request to join'),
            ),
          )
        else if (exam.availability == ExamAvailability.closed)
          Text(
            'This exam has ended.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}
