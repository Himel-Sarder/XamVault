import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/models/join_request.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/providers/providers.dart';

/// Exams in one course, newest first.
final courseExamsProvider =
    FutureProvider.autoDispose.family<List<Exam>, int>((ref, courseId) async {
  final page = await ref.watch(examRepositoryProvider).list(courseId: courseId);
  return page.items;
});

/// One exam, with its settings and derived counts.
final examProvider =
    FutureProvider.autoDispose.family<Exam, int>((ref, examId) async {
  return ref.watch(examRepositoryProvider).get(examId);
});

/// The questions in one exam, in display order.
final examQuestionsProvider =
    FutureProvider.autoDispose.family<List<ExamQuestion>, int>((ref, examId) async {
  return ref.watch(examRepositoryProvider).listQuestions(examId);
});

/// Why an exam can or cannot be published.
///
/// Kept separate from [examProvider] so the Publish button can explain itself before the
/// teacher presses it, rather than only failing afterwards.
final publishCheckProvider =
    FutureProvider.autoDispose.family<PublishCheck, int>((ref, examId) async {
  return ref.watch(examRepositoryProvider).publishCheck(examId);
});

/// Requests to sit one exam, oldest first.
final joinRequestsProvider =
    FutureProvider.autoDispose.family<List<JoinRequest>, int>((ref, examId) async {
  return ref.watch(examRepositoryProvider).listJoinRequests(examId);
});

/// Invalidate everything that depends on one exam after a mutation.
///
/// Takes a [WidgetRef] because it is always called from a screen after a write; the
/// exam, its questions and its publish status all go stale together.
void refreshExam(WidgetRef ref, int examId, {int? courseId}) {
  ref.invalidate(examProvider(examId));
  ref.invalidate(examQuestionsProvider(examId));
  ref.invalidate(publishCheckProvider(examId));
  ref.invalidate(joinRequestsProvider(examId));
  if (courseId != null) ref.invalidate(courseExamsProvider(courseId));
}
