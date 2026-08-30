import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:uniexam/widgets/status_views.dart';

/// What a capture produced.
class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// Photographs a page without leaving the exam.
///
/// The obvious way to do this is the system camera, and that is what it used to do. It
/// cannot work here. The exam pins itself to the screen, and Android will not bring
/// another app forward while it is pinned -- so the pin had to be released first, and
/// releasing it is precisely what puts the phone on its lock screen, because pinning
/// defaults to asking for the PIN before it will let go.
///
/// So the camera runs inside this activity instead. Nothing is unpinned, nothing is
/// launched, and the student never leaves the paper -- which is also the behaviour an
/// invigilator would ask for if anyone had thought to ask them.
class InAppCamera extends StatefulWidget {
  const InAppCamera({super.key, required this.title});

  /// The question being answered, so the student can see what they are photographing
  /// for while the viewfinder is up.
  final String title;

  @override
  State<InAppCamera> createState() => _InAppCameraState();
}

class _InAppCameraState extends State<InAppCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // The camera is a shared device: Android takes it away when we lose the
    // foreground, and holding a dead controller shows a frozen frame.
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'This device has no camera.');
        return;
      }
      // The back camera, where there is one: a page on a desk is in front of the
      // phone, not behind it.
      final chosen = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        chosen,
        // High rather than max: a page of handwriting is legible well before the
        // sensor's limit, and the file has to cross a phone network.
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (error) {
      if (mounted) {
        setState(() => _error = switch (error.code) {
              'CameraAccessDenied' ||
              'CameraAccessDeniedWithoutPrompt' =>
                'The app needs permission to use the camera. '
                    'Allow it in Settings, then try again.',
              _ => 'The camera could not be opened.',
            });
      }
    }
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;

    setState(() => _busy = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(
        CapturedPhoto(bytes: bytes, filename: shot.name),
      );
    } on CameraException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The photograph could not be taken. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          key: const Key('cancel_capture'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        key: const Key('camera_error'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : controller == null
                      ? const LoadingView()
                      : CameraPreview(controller),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Text(
                  'Fill the frame with your page, and keep it flat.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 18),
                _Shutter(
                  onPressed: controller == null || _error != null ? null : _shoot,
                  busy: _busy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take the photograph',
      child: InkWell(
        key: const Key('take_photo'),
        onTap: busy ? null : onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 74,
          height: 74,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: onPressed == null ? Colors.white24 : Colors.white,
              width: 4,
            ),
          ),
          child: busy
              ? const InlineLoader(size: 26, colour: Colors.white)
              : Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onPressed == null ? Colors.white24 : Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
