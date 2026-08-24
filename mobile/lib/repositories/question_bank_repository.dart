import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/bank_question.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/repositories/exam_repository.dart';

/// The teacher's reusable question library (§6).
class QuestionBankRepository {
  const QuestionBankRepository(this._api);

  final ApiClient _api;

  Future<Paged<BankQuestion>> list({
    QuestionType? type,
    String? difficulty,
    String? topic,
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/question-bank',
      query: {
        'page': page,
        'page_size': pageSize,
        'type': ?type?.wire,
        'difficulty': ?difficulty,
        'topic': ?topic,
        'search': ?search,
      },
    );
    return Paged.fromJson(data, BankQuestion.fromJson);
  }

  Future<List<String>> topics() async {
    final data = await _api.get<Map<String, dynamic>>('/question-bank/topics');
    return (data['topics'] as List<dynamic>).cast<String>();
  }

  Future<BankQuestion> create(QuestionDraft draft) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/question-bank',
      data: draft.toJson(),
    );
    return BankQuestion.fromJson(data);
  }

  Future<BankQuestion> update(int questionId, QuestionDraft draft) async {
    final data = await _api.put<Map<String, dynamic>>(
      '/question-bank/$questionId',
      data: draft.toJson(),
    );
    return BankQuestion.fromJson(data);
  }

  Future<void> delete(int questionId) => _api.delete('/question-bank/$questionId');

  /// Attaches library questions to a draft exam, in the order given.
  Future<int> attachToExam(int examId, List<int> questionIds) async {
    final data = await _api.post<List<dynamic>>(
      '/exams/$examId/questions/from-bank',
      data: {'question_ids': questionIds},
    );
    return data.length;
  }
}
