import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/providers/providers.dart';

/// Pick an image, upload it, and hold the URL the server gives back.
///
/// The upload happens immediately rather than at save time, so a rejected file is
/// reported while the teacher is still looking at it.
class ImageField extends ConsumerStatefulWidget {
  const ImageField({
    super.key,
    required this.label,
    required this.url,
    required this.onChanged,
    this.height = 160,
    this.fieldKey,
  });

  final String label;
  final String? url;
  final ValueChanged<String?> onChanged;
  final double height;
  final Key? fieldKey;

  @override
  ConsumerState<ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends ConsumerState<ImageField> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final url = await ref.read(examRepositoryProvider).uploadImage(
            bytes: bytes,
            filename: picked.name,
          );
      widget.onChanged(url);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Could not read that file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Drops the image from the question, and asks the server to forget it.
  ///
  /// The reference goes first and unconditionally: the teacher asked for it gone from
  /// their question, and that must not depend on a network call. Removing the stored
  /// file is a tidy-up on top — if it fails, or the server refuses because another
  /// question still uses those bytes, the question is already correct either way.
  Future<void> _remove(String url) async {
    widget.onChanged(null);
    try {
      await ref.read(examRepositoryProvider).deleteImage(url);
    } on ApiException {
      // Deliberately silent. An orphaned row is not worth interrupting a teacher over.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = widget.url;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (url != null && url.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              AppConfig.mediaUrl(url),
              height: widget.height,
              fit: BoxFit.contain,
              errorBuilder: (context, _, _) => Container(
                height: widget.height,
                alignment: Alignment.center,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Text('Image could not be loaded'),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              key: widget.fieldKey,
              onPressed: _busy ? null : _pick,
              icon: _busy
                  ? const SizedBox(
                      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.image_outlined),
              label: Text(url == null || url.isEmpty ? 'Choose image' : 'Replace'),
            ),
            if (url != null && url.isNotEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                key: Key('remove_${widget.label}'),
                onPressed: _busy ? null : () => _remove(url),
                child: const Text('Remove'),
              ),
            ],
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}
