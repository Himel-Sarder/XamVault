import 'package:flutter/material.dart';
import 'package:uniexam/models/exam.dart';

/// Colour-coded status chip. Draft and Published read very differently to a teacher, so
/// the difference is carried by colour as well as by the word.
class ExamStatusChip extends StatelessWidget {
  const ExamStatusChip({super.key, required this.status});

  final ExamStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      ExamStatus.draft => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      ExamStatus.published => (scheme.primaryContainer, scheme.onPrimaryContainer),
      ExamStatus.running => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      ExamStatus.completed => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      ExamStatus.cancelled => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDateTime(DateTime? value, {String ifNull = 'Not set'}) {
  if (value == null) return ifNull;
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '${value.day} ${_months[value.month - 1]} ${value.year}, $hour:$minute $period';
}

class ExamTile extends StatelessWidget {
  const ExamTile({super.key, required this.exam, this.onTap});

  final Exam exam;
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
                  Expanded(child: Text(exam.title, style: theme.textTheme.titleMedium)),
                  const SizedBox(width: 8),
                  ExamStatusChip(status: exam.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatDateTime(exam.startAt, ifNull: 'No start time set'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '${exam.durationMinutes} min  ·  '
                '${exam.questionCount} question${exam.questionCount == 1 ? '' : 's'}  ·  '
                '${exam.totalMarks} mark${exam.totalMarks == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
