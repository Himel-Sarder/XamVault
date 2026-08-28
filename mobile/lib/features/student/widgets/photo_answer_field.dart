import 'package:flutter/material.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/config/theme.dart';

/// Photograph your work on paper, for a question a keyboard is the wrong tool for.
///
/// The camera opens directly rather than a file picker. That is the point of the
/// question type: the student is meant to photograph the page in front of them, and a
/// gallery would let them attach anything prepared earlier. It is not a control — a
/// determined student can still photograph a photograph — but the honest default is
/// the one that matches what the teacher asked for.
class PhotoAnswerField extends StatelessWidget {
  const PhotoAnswerField({
    super.key,
    required this.urls,
    required this.maxPhotos,
    required this.busy,
    required this.onCapture,
    required this.onRemove,
  });

  final List<String> urls;
  final int maxPhotos;

  /// True while an upload is in flight. The button says so rather than going dead.
  final bool busy;

  final VoidCallback onCapture;
  final void Function(String url) onRemove;

  bool get _isFull => urls.length >= maxPhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = urls.isEmpty ? context.status.warning : context.status.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tint.container,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 20, color: tint.foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  urls.isEmpty
                      ? 'Answer on paper, then photograph it. Up to $maxPhotos photos.'
                      : '${urls.length} of $maxPhotos photos added',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tint.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (urls.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _Thumbnail(
                key: Key('answer_photo_$index'),
                url: urls[index],
                index: index,
                onRemove: busy ? null : () => onRemove(urls[index]),
                onOpen: () => _open(context, urls[index], index),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('capture_photo'),
            // Full is a state to explain, not a dead button with no reason given.
            onPressed: busy || _isFull ? null : onCapture,
            icon: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.photo_camera),
            label: Text(
              busy
                  ? 'Uploading...'
                  : _isFull
                      ? 'All $maxPhotos photos added'
                      : urls.isEmpty
                          ? 'Open camera'
                          : 'Add another photo',
            ),
          ),
        ),
        if (_isFull) ...[
          const SizedBox(height: 8),
          Text(
            'Remove one to take a different photo.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  /// Full screen, because a marker's legibility question is the student's too: a
  /// thumbnail cannot show whether the handwriting came out readable.
  void _open(BuildContext context, String url, int index) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Photo ${index + 1}'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.network(AppConfig.mediaUrl(url)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    super.key,
    required this.url,
    required this.index,
    required this.onRemove,
    required this.onOpen,
  });

  final String url;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        GestureDetector(
          onTap: onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              AppConfig.mediaUrl(url),
              width: 130,
              height: 150,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => Container(
                width: 130,
                height: 150,
                alignment: Alignment.center,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: context.status.danger.foreground,
            shape: const CircleBorder(),
            child: InkWell(
              key: Key('remove_photo_$index'),
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
