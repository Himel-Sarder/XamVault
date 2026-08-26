<<<<<<< HEAD
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/models/bank_question.dart';
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

/// The teacher's library, filtered.
typedef BankFilter = ({QuestionType? type, String? difficulty, String? topic, String? search});

final questionBankProvider =
    FutureProvider.autoDispose.family<List<BankQuestion>, BankFilter>((ref, filter) async {
  final page = await ref.watch(questionBankRepositoryProvider).list(
        type: filter.type,
        difficulty: filter.difficulty,
        topic: filter.topic,
        search: filter.search,
      );
  return page.items;
});

final bankTopicsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.watch(questionBankRepositoryProvider).topics();
});
=======
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/models/bank_question.dart';
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

/// The teacher's library, filtered.
typedef BankFilter = ({QuestionType? type, String? difficulty, String? topic, String? search});

final questionBankProvider =
    FutureProvider.autoDispose.family<List<BankQuestion>, BankFilter>((ref, filter) async {
  final page = await ref.watch(questionBankRepositoryProvider).list(
        type: filter.type,
        difficulty: filter.difficulty,
        topic: filter.topic,
        search: filter.search,
      );
  return page.items;
});

final bankTopicsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.watch(questionBankRepositoryProvider).topics();
});
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
