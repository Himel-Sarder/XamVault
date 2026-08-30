import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the platform actually granted when asked to lock down.
///
/// Reported honestly rather than optimistically: on an unmanaged phone `lockTask` is
/// usually screen *pinning*, which the student can dismiss, and the app says so instead
/// of implying a protection it does not have (§38).
class LockdownStatus {
  const LockdownStatus({
    required this.secureFlag,
    required this.immersive,
    required this.lockTask,
    required this.lockTaskIsPinning,
    required this.detail,
  });

  const LockdownStatus.unavailable(this.detail)
      : secureFlag = false,
        immersive = false,
        lockTask = false,
        lockTaskIsPinning = false;

  final bool secureFlag;
  final bool immersive;
  final bool lockTask;

  /// True when the lock is the dismissible pinning variant, not device-policy lockdown.
  final bool lockTaskIsPinning;
  final String detail;

  /// True only when the platform is genuinely holding the app in place.
  bool get isFullyLocked => lockTask && !lockTaskIsPinning;

  /// The screenshot block is the one control an unmanaged device really enforces.
  bool get blocksScreenCapture => secureFlag;

  factory LockdownStatus.fromMap(Map<Object?, Object?> map) => LockdownStatus(
        secureFlag: map['secureFlag'] as bool? ?? false,
        immersive: map['immersive'] as bool? ?? false,
        lockTask: map['lockTask'] as bool? ?? false,
        lockTaskIsPinning: map['lockTaskIsPinning'] as bool? ?? false,
        detail: map['detail'] as String? ?? '',
      );
}

/// One observation from the device, on its way to the server.
class SecurityObservation {
  const SecurityObservation(this.eventType, [this.metadata]);

  final String eventType;
  final Map<String, Object?>? metadata;

  Map<String, Object?> toJson() => {
        'event_type': eventType,
        if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
      };
}

/// The Flutter side of the Android lockdown bridge (§37).
///
/// On any platform without the native side — Chrome, iOS, tests — every call returns a
/// clear "unavailable" rather than throwing, so the exam still runs and the *absence* of
/// protection is itself recorded.
class ExamSecurity {
  ExamSecurity({MethodChannel? control, MethodChannel? events})
      : _control = control ?? const MethodChannel('com.uniexam/exam_security'),
        _events = events ?? const MethodChannel('com.uniexam/exam_events');

  final MethodChannel _control;
  final MethodChannel _events;

  final StreamController<SecurityObservation> _observations =
      StreamController<SecurityObservation>.broadcast();

  /// Events pushed up from Android: backgrounding, network changes, clock changes.
  Stream<SecurityObservation> get observations => _observations.stream;

  bool _listening = false;

  /// Only Android has the native side; elsewhere the app degrades openly.
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void startListening() {
    if (_listening) return;
    _listening = true;
    _events.setMethodCallHandler((call) async {
      if (call.method != 'onSecurityEvent') return null;
      final payload = (call.arguments as Map?)?.cast<Object?, Object?>() ?? {};
      final type = payload['event_type'] as String?;
      if (type == null) return null;
      final metadata = (payload['metadata'] as Map?)?.cast<String, Object?>();
      _observations.add(SecurityObservation(type, metadata));
      return null;
    });
  }

  Future<LockdownStatus> enter() async {
    if (!isSupported) {
      return const LockdownStatus.unavailable(
        'Device lockdown is only available in the Android app',
      );
    }
    try {
      final result = await _control.invokeMethod<Map<Object?, Object?>>('enterExamLockdown');
      return result == null
          ? const LockdownStatus.unavailable('No response from the device')
          : LockdownStatus.fromMap(result);
    } on PlatformException catch (error) {
      return LockdownStatus.unavailable(error.message ?? 'Lockdown failed');
    } on MissingPluginException {
      return const LockdownStatus.unavailable('Device lockdown is not available here');
    }
  }

  /// Lets the app send the student to another app on purpose, and take the lock back.
  ///
  /// A pinned app cannot launch the camera -- Android refuses to bring another
  /// activity forward, and the student sees the exam apparently close and reopen. A
  /// PHOTO_ANSWER question needs that launch, so the pin is released around it.
  ///
  /// Returns whether anything was actually released, which is false when no lockdown
  /// was engaged in the first place.
  Future<bool> beginExcursion() async {
    if (!isSupported) return false;
    try {
      return await _control.invokeMethod<bool>('beginExcursion') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Retakes the lock after an excursion. False if it could not be regained -- worth
  /// knowing, but never worth blocking the student's answer over.
  Future<bool> endExcursion() async {
    if (!isSupported) return false;
    try {
      return await _control.invokeMethod<bool>('endExcursion') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> exit() async {
    if (!isSupported) return;
    try {
      await _control.invokeMethod<Map<Object?, Object?>>('exitExamLockdown');
    } on PlatformException {
      // Leaving the exam must never be blocked by a failure to release the lock.
    } on MissingPluginException {
      // Nothing was engaged.
    }
  }

  void dispose() {
    _events.setMethodCallHandler(null);
    _listening = false;
    _observations.close();
  }
}
