import 'package:flutter/material.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/student_exam.dart';

/// Availability and request status carry different meanings, so they get different
/// chips rather than one combined label.
class AvailabilityChip extends StatelessWidget {
  const AvailabilityChip({super.key, required this.availability});

  final ExamAvailability availability;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (availability) {
      ExamAvailability.upcoming => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      ExamAvailability.open => (scheme.primaryContainer, scheme.onPrimaryContainer),
      ExamAvailability.closed => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return _Pill(label: availability.label, background: background, foreground: foreground);
  }
}

class JoinStatusChip extends StatelessWidget {
  const JoinStatusChip({super.key, required this.status});

  final JoinRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      JoinRequestStatus.none => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      JoinRequestStatus.pending => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      JoinRequestStatus.approved => (scheme.primaryContainer, scheme.onPrimaryContainer),
      JoinRequestStatus.rejected => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return _Pill(label: status.label, background: background, foreground: foreground);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class StudentExamTile extends StatelessWidget {
  const StudentExamTile({super.key, required this.exam, this.onTap});

  final StudentExam exam;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
              const SizedBox(height: 6),
              Text(exam.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                formatDateTime(exam.startAt, ifNull: 'Start time not set'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '${exam.durationMinutes} min  ·  ${exam.questionCount} questions  ·  '
                '${exam.totalMarks} marks',
                style: theme.textTheme.bodySmall,
              ),
              if (exam.joinRequestStatus != JoinRequestStatus.none) ...[
                const SizedBox(height: 10),
                JoinStatusChip(status: exam.joinRequestStatus),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
