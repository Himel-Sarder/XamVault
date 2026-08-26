import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/join_request.dart';
import 'package:uniexam/models/student_exam.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

/// Exams the signed-in student may sit. The backend decides what that means.
///
/// The signed-in user's id is watched purely as a cache key, so switching account
/// refetches rather than showing the previous student's list. It is not an access
/// check - the API is the only thing that decides what may be read.
final availableExamsProvider =
    FutureProvider.autoDispose<List<StudentExam>>((ref) async {
  ref.watch(authProvider.select((state) => state.user?.id));
  final page = await ref.watch(studentRepositoryProvider).availableExams();
  return page.items;
});

final studentExamProvider =
    FutureProvider.autoDispose.family<StudentExam, int>((ref, examId) async {
  return ref.watch(studentRepositoryProvider).exam(examId);
});

final myRequestsProvider = FutureProvider.autoDispose<List<MyJoinRequest>>((ref) async {
  ref.watch(authProvider.select((state) => state.user?.id));
  return ref.watch(studentRepositoryProvider).myRequests();
});

/// After requesting to join, the exam's own state changes too (`join_request_status`),
/// so both views go stale together.
void refreshStudentExam(WidgetRef ref, int examId) {
  ref.invalidate(studentExamProvider(examId));
  ref.invalidate(availableExamsProvider);
  ref.invalidate(myRequestsProvider);
}
