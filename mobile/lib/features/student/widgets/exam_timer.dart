import 'package:flutter/material.dart';

String formatCountdown(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = secs.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// The countdown as the student sees it.
///
/// It is a *display* of the server's figure, re-synced on every request. It turns
/// amber under five minutes and red under one, so running out is never a surprise.
class ExamTimer extends StatelessWidget {
  const ExamTimer({super.key, required this.remainingSeconds});

  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (remainingSeconds) {
      <= 60 => (scheme.errorContainer, scheme.onErrorContainer),
      <= 300 => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      key: const Key('exam_timer'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: foreground),
          const SizedBox(width: 6),
          Text(
            formatCountdown(remainingSeconds),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

/// The 1..n grid a student uses to jump around the paper (§59).
class QuestionPalette extends StatelessWidget {
  const QuestionPalette({
    super.key,
    required this.total,
    required this.currentIndex,
    required this.answered,
    required this.onSelect,
    this.enabled = true,
  });

  final int total;
  final int currentIndex;

  /// Indices (0-based) that already have an answer.
  final Set<int> answered;
  final ValueChanged<int> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < total; index++)
          _cell(context, index, scheme),
      ],
    );
  }

  Widget _cell(BuildContext context, int index, ColorScheme scheme) {
    final isCurrent = index == currentIndex;
    final isAnswered = answered.contains(index);
    final (background, foreground) = switch ((isCurrent, isAnswered)) {
      (true, _) => (scheme.primary, scheme.onPrimary),
      (false, true) => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isCurrent ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          key: Key('palette_${index + 1}'),
          onTap: enabled ? () => onSelect(index) : null,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              '${index + 1}',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
