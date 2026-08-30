import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/exam_security.dart';
import 'package:uniexam/models/attempt.dart';
import 'package:uniexam/models/security_summary.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/providers/student_provider.dart';
import 'package:uniexam/repositories/student_repository.dart';

/// Everything the exam screen renders.
class AttemptView {
  const AttemptView({
    required this.attempt,
    required this.remainingSeconds,
    required this.index,
    this.savingQuestionId,
    this.capturingQuestionId,
    this.submitting = false,
    this.outcome,
    this.error,
    this.lockdown,
  });

  final Attempt attempt;

  /// Ticked down locally for a smooth countdown, and overwritten by the server's own
  /// figure on every request. The device clock is never consulted (§34).
  final int remainingSeconds;
  final int index;
  final int? savingQuestionId;

  /// The question whose photograph is being uploaded, if any.
  final int? capturingQuestionId;
  final bool submitting;
  final SubmitOutcome? outcome;
  final String? error;

  /// What device lockdown the platform actually granted, if the exam asked for any.
  /// Null until the attempt loads; unavailable is reported honestly, not hidden.
  final LockdownStatus? lockdown;

  AttemptQuestion get question => attempt.questions[index];
  bool get isFirst => index == 0;
  bool get isLast => index >= attempt.questions.length - 1;
  bool get isFinished => outcome != null || !attempt.isActive;

  AttemptView copyWith({
    Attempt? attempt,
    int? remainingSeconds,
    int? index,
    int? savingQuestionId,
    bool clearSaving = false,
    int? capturingQuestionId,
    bool clearCapturing = false,
    bool? submitting,
    SubmitOutcome? outcome,
    String? error,
    bool clearError = false,
    LockdownStatus? lockdown,
  }) {
    return AttemptView(
      attempt: attempt ?? this.attempt,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      index: index ?? this.index,
      savingQuestionId: clearSaving ? null : (savingQuestionId ?? this.savingQuestionId),
      capturingQuestionId:
          clearCapturing ? null : (capturingQuestionId ?? this.capturingQuestionId),
      submitting: submitting ?? this.submitting,
      outcome: outcome ?? this.outcome,
      error: clearError ? null : (error ?? this.error),
      lockdown: lockdown ?? this.lockdown,
    );
  }
}

/// Drives one exam sitting.
class AttemptController extends AutoDisposeFamilyAsyncNotifier<AttemptView, int> {
  Timer? _ticker;
  Timer? _writeDebounce;
  Timer? _eventFlush;
  StreamSubscription<SecurityObservation>? _observations;

  /// Observations wait here briefly and go up as one batch — a backgrounded app often
  /// produces two events within a second, and a report must never delay the exam.
  final List<SecurityObservation> _pendingEvents = [];

  @override
  Future<AttemptView> build(int attemptId) async {
    ref.onDispose(() {
      _ticker?.cancel();
      _writeDebounce?.cancel();
      _eventFlush?.cancel();
      _observations?.cancel();
    });
    final attempt = await ref.read(studentRepositoryProvider).attempt(attemptId);
    if (!attempt.isActive) {
      return AttemptView(
        attempt: attempt,
        remainingSeconds: attempt.remainingSeconds,
        index: 0,
      );
    }

    _startTicker();
    final lockdown = await _engageLockdown(attempt);
    return AttemptView(
      attempt: attempt,
      remainingSeconds: attempt.remainingSeconds,
      index: 0,
      lockdown: lockdown,
    );
  }

  /// Turns on whatever device protection this exam asked for.
  ///
  /// Nothing in here may stop the exam opening. Locking the device down is a deterrent
  /// on hardware the university does not control; a paper that refuses to start is a
  /// student who cannot sit it. So every failure -- a platform that says no, a channel
  /// that is not there, an exception nobody predicted -- is recorded and swallowed, and
  /// the attempt loads regardless.
  Future<LockdownStatus?> _engageLockdown(Attempt attempt) async {
    if (!attempt.secureMode) return null;

    try {
      final security = ref.read(examSecurityProvider);

      security.startListening();
      _observations = security.observations.listen(_queueEvent);

      final status = await security.enter();
      // Record what actually happened, including that nothing did. A teacher reading
      // the trail should be able to see that an exam ran without device protection.
      _queueEvent(
        status.isFullyLocked || status.blocksScreenCapture
            ? SecurityObservation('LOCKDOWN_ENGAGED', {'detail': status.detail})
            : SecurityObservation('LOCKDOWN_UNAVAILABLE', {'detail': status.detail}),
      );
      return status;
    } catch (error) {
      _queueEvent(SecurityObservation(
        'LOCKDOWN_UNAVAILABLE',
        {'detail': 'The device refused to lock down: $error'},
      ));
      return const LockdownStatus.unavailable('The device refused to lock down');
    }
  }

  void _queueEvent(SecurityObservation observation) {
    _pendingEvents.add(observation);
    _eventFlush?.cancel();
    _eventFlush = Timer(const Duration(seconds: 2), () => unawaited(_flushEvents()));
  }

  Future<void> _flushEvents() async {
    if (_pendingEvents.isEmpty) return;
    final batch = List<SecurityObservation>.of(_pendingEvents);
    _pendingEvents.clear();
    try {
      await ref
          .read(studentRepositoryProvider)
          .reportSecurityEvents(arg, batch);
    } on ApiException {
      // Reporting is best-effort: a failed report must never interrupt an exam, and the
      // events are not worth re-queueing indefinitely.
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final view = state.valueOrNull;
      if (view == null || view.isFinished) return;
      final next = view.remainingSeconds - 1;
      if (next <= 0) {
        state = AsyncData(view.copyWith(remainingSeconds: 0));
        _ticker?.cancel();
        // The countdown running out is not itself a submission — the app asks the
        // server to close the attempt, and the server decides (§42).
        unawaited(submit(auto: true));
        return;
      }
      state = AsyncData(view.copyWith(remainingSeconds: next));
    });
  }

  void goTo(int index) {
    final view = state.valueOrNull;
    if (view == null) return;
    if (index < 0 || index >= view.attempt.questions.length) return;
    // Leaving a question must not lose what was typed on it.
    unawaited(flushPendingWrite());
    state = AsyncData(view.copyWith(index: index, clearError: true));
  }

  void next() => goTo((state.valueOrNull?.index ?? 0) + 1);

  void previous() {
    final view = state.valueOrNull;
    if (view == null || !view.attempt.allowBackNavigation) return;
    goTo(view.index - 1);
  }

  /// Saves a written answer, a short pause after typing stops.
  ///
  /// Debounced because this fires on every keystroke: one request per character would
  /// swamp the connection and, on a slow link, arrive out of order.
  void write(int examQuestionId, String text) {
    final view = state.valueOrNull;
    if (view == null || view.isFinished) return;

    final updated = view.attempt.questions
        .map((item) => item.examQuestionId == examQuestionId
            ? item.copyWith(answerText: text, clearText: text.isEmpty)
            : item)
        .toList(growable: false);
    state = AsyncData(view.copyWith(
      attempt: view.attempt.copyWith(questions: updated),
      clearError: true,
    ));

    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(_flushWrite(examQuestionId, text));
    });
  }

  /// Sends any pending keystrokes now — used before submitting, and when the student
  /// moves to another question, so nothing typed is lost.
  Future<void> flushPendingWrite() async {
    final pending = _writeDebounce;
    if (pending == null || !pending.isActive) return;
    pending.cancel();
    final view = state.valueOrNull;
    if (view == null) return;
    final question = view.question;
    await _flushWrite(question.examQuestionId, question.answerText ?? '');
  }

  Future<void> _flushWrite(int examQuestionId, String text) async {
    final view = state.valueOrNull;
    if (view == null || view.isFinished) return;
    try {
      final ack = await ref.read(studentRepositoryProvider).saveAnswer(
            view.attempt.id,
            examQuestionId: examQuestionId,
            answerText: text,
          );
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncData(current.copyWith(
        attempt: current.attempt.copyWith(answeredCount: ack.answeredCount),
        remainingSeconds: ack.remainingSeconds,
      ));
    } on ApiException catch (error) {
      await _reload(error.message);
    }
  }

  /// Saves one answer. Tapping the selected option again clears it.
  Future<void> select(int examQuestionId, int optionId) async {
    final view = state.valueOrNull;
    if (view == null || view.isFinished) return;

    final question = view.attempt.questions
        .firstWhere((item) => item.examQuestionId == examQuestionId);
    final chosen = question.selectedOptionId == optionId ? null : optionId;

    // Optimistic: the tap shows immediately, and the server's answer replaces it.
    final updated = view.attempt.questions
        .map((item) => item.examQuestionId == examQuestionId
            ? item.copyWith(selectedOptionId: chosen, clearSelection: chosen == null)
            : item)
        .toList(growable: false);
    state = AsyncData(view.copyWith(
      attempt: view.attempt.copyWith(questions: updated),
      savingQuestionId: examQuestionId,
      clearError: true,
    ));

    try {
      final ack = await ref.read(studentRepositoryProvider).saveAnswer(
            view.attempt.id,
            examQuestionId: examQuestionId,
            selectedOptionId: chosen,
          );
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncData(current.copyWith(
        attempt: current.attempt.copyWith(answeredCount: ack.answeredCount),
        remainingSeconds: ack.remainingSeconds,
        clearSaving: true,
      ));
    } on ApiException catch (error) {
      // The optimistic edit is rolled back by re-reading the server's own state.
      await _reload(error.message);
    }
  }

  /// The cap the button enforces. The server enforces its own, and that one is the
  /// real limit — this exists so the button can explain itself before being tapped.
  static const int maxAnswerPhotos = 3;

  /// Stores a photograph the student has just taken, and uploads it.
  ///
  /// The capture itself happens in the exam's own screen rather than in the system
  /// camera. The obvious implementation launched the camera app, and it could not
  /// work: the exam is pinned to the screen, Android will not bring another app
  /// forward while it is, and releasing the pin to allow it is what put the phone on
  /// its lock screen -- pinning asks for the PIN before it lets go.
  ///
  /// So the bytes arrive already captured. Nothing is unpinned and the student never
  /// leaves the paper.
  Future<void> uploadPhoto(
    int examQuestionId, {
    required Uint8List bytes,
    required String filename,
  }) async {
    final view = state.valueOrNull;
    if (view == null || view.isFinished || view.capturingQuestionId != null) return;

    state = AsyncData(view.copyWith(
      capturingQuestionId: examQuestionId,
      clearError: true,
    ));
    try {
      final ack = await ref.read(studentRepositoryProvider).addAnswerPhoto(
            arg,
            examQuestionId: examQuestionId,
            bytes: bytes,
            filename: filename,
          );
      _applyPhotos(examQuestionId, ack);
    } on ApiException catch (error) {
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(current.copyWith(
          error: error.message,
          clearCapturing: true,
        ));
      }
    }
  }

  Future<void> removePhoto(int examQuestionId, String url) async {
    final view = state.valueOrNull;
    if (view == null || view.isFinished) return;

    state = AsyncData(view.copyWith(
      capturingQuestionId: examQuestionId,
      clearError: true,
    ));
    try {
      final ack = await ref.read(studentRepositoryProvider).removeAnswerPhoto(
            arg,
            examQuestionId: examQuestionId,
            url: url,
          );
      _applyPhotos(examQuestionId, ack);
    } on ApiException catch (error) {
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(current.copyWith(
          error: error.message,
          clearCapturing: true,
        ));
      }
    }
  }

  /// Takes the server's list rather than the client's guess, so a refused upload
  /// cannot leave a photograph on screen that was never stored.
  void _applyPhotos(int examQuestionId, AnswerAck ack) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.attempt.questions
        .map((item) => item.examQuestionId == examQuestionId
            ? item.copyWith(answerImageUrls: ack.answerImageUrls)
            : item)
        .toList(growable: false);

    state = AsyncData(current.copyWith(
      attempt: current.attempt.copyWith(
        questions: updated,
        answeredCount: ack.answeredCount,
      ),
      remainingSeconds: ack.remainingSeconds,
      clearCapturing: true,
    ));
  }

  Future<void> submit({bool auto = false}) async {
    final view = state.valueOrNull;
    if (view == null || view.submitting || view.isFinished) return;
    await flushPendingWrite();
    state = AsyncData(view.copyWith(submitting: true, clearError: true));

    try {
      final outcome = await ref.read(studentRepositoryProvider).submit(view.attempt.id);
      _ticker?.cancel();
      // Release the device before anything else: a student must never be left pinned
      // inside a finished exam.
      await _releaseLockdown();
      final current = state.valueOrNull ?? view;
      state = AsyncData(current.copyWith(
        submitting: false,
        outcome: outcome,
        remainingSeconds: 0,
        attempt: current.attempt.copyWith(status: outcome.status),
      ));
      ref.invalidate(availableExamsProvider);
      ref.invalidate(myResultsProvider);
    } on ApiException catch (error) {
      if (auto) {
        // The server may have closed the attempt already; its state is the truth.
        await _reload(null);
        return;
      }
      final current = state.valueOrNull ?? view;
      state = AsyncData(current.copyWith(submitting: false, error: error.message));
    }
  }

  Future<void> _releaseLockdown() async {
    // Release the device first. Leaving a student pinned inside a finished exam while
    // waiting on a network call would be the worst possible failure here.
    await ref.read(examSecurityProvider).exit();

    _eventFlush?.cancel();
    await _observations?.cancel();
    _observations = null;
    await _flushEvents();
  }

  Future<void> _reload(String? message) async {
    try {
      final fresh = await ref.read(studentRepositoryProvider).attempt(arg);
      final current = state.valueOrNull;
      state = AsyncData(
        AttemptView(
          attempt: fresh,
          remainingSeconds: fresh.remainingSeconds,
          index: current?.index ?? 0,
          error: message,
        ),
      );
      if (!fresh.isActive) _ticker?.cancel();
    } on ApiException catch (error) {
      state = AsyncError(error, StackTrace.current);
    }
  }
}

final attemptControllerProvider =
    AsyncNotifierProvider.autoDispose.family<AttemptController, AttemptView, int>(
  AttemptController.new,
);

final myResultsProvider = FutureProvider.autoDispose((ref) async {
  return ref.watch(studentRepositoryProvider).myResults();
});

final examResultsProvider =
    FutureProvider.autoDispose.family((ref, int examId) async {
  return ref.watch(examRepositoryProvider).examResults(examId);
});

final gradingQueueProvider =
    FutureProvider.autoDispose.family((ref, int examId) async {
  return ref.watch(examRepositoryProvider).gradingQueue(examId);
});

final attemptGradingProvider =
    FutureProvider.autoDispose.family((ref, int attemptId) async {
  return ref.watch(examRepositoryProvider).answersToMark(attemptId);
});

/// Analytics for one exam at a chosen pass threshold.
final examAnalyticsProvider = FutureProvider.autoDispose
    .family((ref, ({int examId, double passPercentage}) args) async {
  return ref
      .watch(examRepositoryProvider)
      .analytics(args.examId, passPercentage: args.passPercentage);
});

/// What every student's device reported during one exam.
///
/// Named for activity rather than security to keep it distinct from
/// [examSecurityProvider], which is the device lockdown channel.
final examActivityProvider =
    FutureProvider.autoDispose.family<ExamSecuritySummary, int>((ref, examId) async {
  return ref.watch(examRepositoryProvider).securitySummary(examId);
});

/// The full trail behind one row.
final attemptActivityProvider =
    FutureProvider.autoDispose.family<AttemptSecurityReport, int>((ref, attemptId) async {
  return ref.watch(examRepositoryProvider).attemptSecurity(attemptId);
});
