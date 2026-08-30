import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/providers/attempt_provider.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

/// image_picker is Pigeon-based, so there is no stable channel name to fake the camera
/// with. Under test its platform call simply fails, which lands `capturePhoto` on its
/// error path -- and that path is the one that most needs to restore the lock, so the
/// invariant is still the thing being checked.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeStudentRepository student;
  late FakeExamSecurity security;
  late ProviderContainer container;

  setUp(() {
    student = FakeStudentRepository()
      ..currentAttempt = buildAttempt(
        secureMode: true,
        questionCount: 1,
        writtenTypes: const {0: 'PHOTO_ANSWER'},
      );
    security = FakeExamSecurity();
    container = ProviderContainer(overrides: [
      studentRepositoryProvider.overrideWithValue(student),
      examSecurityProvider.overrideWithValue(security),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> capture() async {
    final notifier = container.read(attemptControllerProvider(900).notifier);
    await container.read(attemptControllerProvider(900).future);
    await notifier.capturePhoto(100);
  }

  test('the screen is unpinned before the camera is asked for', () async {
    // A pinned app cannot bring the camera forward: Android refuses, and what the
    // student sees is the exam closing and reopening. This is the whole bug, so the
    // release has to come first -- not after the picture comes back.
    await capture();

    expect(security.excursions.first, isTrue,
        reason: 'the camera was opened while the screen was still pinned');
  });

  test('the lock is taken back afterwards', () async {
    await capture();

    expect(security.excursions, [true, false]);
    expect(security.locked, isTrue);
  });

  test('a camera that never opens still restores the lock', () async {
    // The path that matters most: if releasing the pin were not paired with retaking
    // it, one refused camera would leave the rest of the paper unpinned.
    await capture();

    expect(security.locked, isTrue);
  });

  test('capturing twice leaves the lock held, not doubly released', () async {
    await capture();
    await capture();

    expect(security.excursions, [true, false, true, false]);
    expect(security.locked, isTrue);
  });
}
