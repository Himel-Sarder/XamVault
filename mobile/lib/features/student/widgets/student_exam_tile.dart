import 'package:flutter/material.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/student_exam.dart';
import 'package:uniexam/widgets/status_pill.dart';

/// Availability and request status carry different meanings, so they get different
/// chips rather than one combined label.
class AvailabilityChip extends StatelessWidget {
  const AvailabilityChip({super.key, required this.availability});

  final ExamAvailability availability;

  @override
  Widget build(BuildContext context) {
    final palette = context.status;
    final colour = switch (availability) {
      ExamAvailability.upcoming => palette.info,
      // Sittable now. This is the one a student is looking for.
      ExamAvailability.open => palette.success,
      ExamAvailability.closed => palette.neutral,
    };
    return StatusPill(label: availability.label, colour: colour);
  }
}

class JoinStatusChip extends StatelessWidget {
  const JoinStatusChip({super.key, required this.status});

  final JoinRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.status;
    final colour = switch (status) {
      JoinRequestStatus.none => palette.neutral,
      // Waiting on a teacher. Amber is what a reader already reads as "not yet".
      JoinRequestStatus.pending => palette.warning,
      JoinRequestStatus.approved => palette.success,
      JoinRequestStatus.rejected => palette.danger,
    };
    return StatusPill(label: status.label, colour: colour);
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
