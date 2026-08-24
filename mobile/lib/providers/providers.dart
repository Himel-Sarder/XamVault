import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/core/exam_security.dart';
import 'package:uniexam/core/token_manager.dart';
import 'package:uniexam/core/token_store.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/repositories/auth_repository.dart';
import 'package:uniexam/repositories/course_repository.dart';
import 'package:uniexam/repositories/exam_repository.dart';
import 'package:uniexam/repositories/notification_repository.dart';
import 'package:uniexam/repositories/question_bank_repository.dart';
import 'package:uniexam/repositories/student_repository.dart';

/// Overridden in tests with [InMemoryTokenStore].
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final tokenManagerProvider = Provider<TokenManager>(
  (ref) => TokenManager(ref.watch(tokenStoreProvider)),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenManager: ref.watch(tokenManagerProvider),
    // Read lazily: this fires long after both providers are built, so there is no
    // circular initialisation between the client and the auth controller.
    onSessionExpired: () => ref.read(authProvider.notifier).handleSessionExpired(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final courseRepositoryProvider = Provider<CourseRepository>(
  (ref) => CourseRepository(ref.watch(apiClientProvider)),
);

final examRepositoryProvider = Provider<ExamRepository>(
  (ref) => ExamRepository(ref.watch(apiClientProvider)),
);

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(ref.watch(apiClientProvider)),
);

/// Overridden in tests with a fake so the exam screen can be driven without a device.
final examSecurityProvider = Provider<ExamSecurity>((ref) {
  final security = ExamSecurity();
  ref.onDispose(security.dispose);
  return security;
});

final questionBankRepositoryProvider = Provider<QuestionBankRepository>(
  (ref) => QuestionBankRepository(ref.watch(apiClientProvider)),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(apiClientProvider)),
);
