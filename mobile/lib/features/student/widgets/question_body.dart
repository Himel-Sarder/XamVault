import 'package:flutter/material.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/models/attempt.dart';

/// An image that says so when it cannot load, rather than showing a broken box.
class QuestionImage extends StatelessWidget {
  const QuestionImage({super.key, required this.path, this.height = 220});

  final String path;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        AppConfig.mediaUrl(path),
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, _, _) => Container(
          height: height,
          alignment: Alignment.center,
          color: scheme.surfaceContainerHighest,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('Image could not be loaded',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option, text or image, with the selection state shown either way.
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AttemptOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = option.optionImageUrl != null && option.optionImageUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: Key('option_${option.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment:
                  hasImage ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: hasImage
                      ? QuestionImage(path: option.optionImageUrl!, height: 140)
                      : Text(
                          option.optionText ?? '',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain writing area for SHORT_ANSWER.
class ShortAnswerField extends StatelessWidget {
  const ShortAnswerField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('short_answer_field'),
      controller: controller,
      onChanged: onChanged,
      enabled: enabled,
      maxLines: 10,
      minLines: 6,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Write your answer here…',
        alignLabelWithHint: true,
      ),
    );
  }
}

/// A monospaced editor for CODE_ANSWER, with the question's limits stated above it.
///
/// Deliberately plain: syntax highlighting would be pleasant, but nothing here executes
/// the code, and pretending otherwise would be misleading.
class CodeAnswerField extends StatelessWidget {
  const CodeAnswerField({
    super.key,
    required this.question,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });

  final AttemptQuestion question;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limits = <String>[
      if (question.language != null) question.language!.toUpperCase(),
      if (question.timeLimitSeconds != null) '${question.timeLimitSeconds}s time limit',
      if (question.memoryLimitMb != null) '${question.memoryLimitMb} MB memory',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (limits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final limit in limits)
                  Chip(
                    label: Text(limit),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
              ],
            ),
          ),
        TextField(
          key: const Key('code_answer_field'),
          controller: controller,
          onChanged: onChanged,
          enabled: enabled,
          maxLines: 18,
          minLines: 10,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Write your program here…',
            hintStyle: const TextStyle(fontFamily: 'monospace'),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your teacher marks this answer after the exam.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
