import 'package:dio/dio.dart';
import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/models/analytics.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/models/exam_result.dart';
import 'package:uniexam/models/join_request.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/models/question.dart';

/// Teacher-side exam and question operations.
///
/// Every scoping and permission decision is the server's; this only shapes requests.
class ExamRepository {
  const ExamRepository(this._api);

  final ApiClient _api;

  // -------------------------------------------------------------- exams

  Future<Paged<Exam>> list({int? courseId, int page = 1, int pageSize = 50}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/exams',
      query: {
        'page': page,
        'page_size': pageSize,
        'course_id': ?courseId,
      },
    );
    return Paged.fromJson(data, Exam.fromJson);
  }

  Future<Exam> get(int examId) async {
    final data = await _api.get<Map<String, dynamic>>('/exams/$examId');
    return Exam.fromJson(data);
  }

  Future<Exam> create({
    required int courseId,
    required String title,
    required int durationMinutes,
    String? description,
    DateTime? startAt,
    ExamSettings? settings,
  }) async {
    final data = await _api.post<Map<String, dynamic>>('/exams', data: {
      'course_id': courseId,
      'title': title,
      'duration_minutes': durationMinutes,
      if (description != null && description.isNotEmpty) 'description': description,
      // The server owns every timestamp; send UTC so there is no ambiguity about
      // which clock a naive local time belonged to.
      if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
      if (settings != null) 'settings': settings.toJson(),
    });
    return Exam.fromJson(data);
  }

  Future<Exam> update(
    int examId, {
    String? title,
    String? description,
    DateTime? startAt,
    int? durationMinutes,
  }) async {
    final data = await _api.patch<Map<String, dynamic>>('/exams/$examId', data: {
      'title': ?title,
      'description': ?description,
      if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
      'duration_minutes': ?durationMinutes,
    });
    return Exam.fromJson(data);
  }

  Future<Exam> updateSettings(int examId, ExamSettings settings) async {
    final data = await _api.put<Map<String, dynamic>>(
      '/exams/$examId/settings',
      data: settings.toJson(),
    );
    return Exam.fromJson(data);
  }

  Future<void> delete(int examId) => _api.delete('/exams/$examId');

  // ------------------------------------------------------------ publish

  Future<PublishCheck> publishCheck(int examId) async {
    final data = await _api.get<Map<String, dynamic>>('/exams/$examId/publish-check');
    return PublishCheck.fromJson(data);
  }

  Future<Exam> publish(int examId) async {
    final data = await _api.post<Map<String, dynamic>>('/exams/$examId/publish');
    return Exam.fromJson(data);
  }

  // ---------------------------------------------------------- questions

  Future<List<ExamQuestion>> listQuestions(int examId) async {
    final data = await _api.get<List<dynamic>>('/exams/$examId/questions');
    return data
        .map((item) => ExamQuestion.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ExamQuestion> addQuestion(int examId, QuestionDraft draft) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/exams/$examId/questions',
      data: draft.toJson(),
    );
    return ExamQuestion.fromJson(data);
  }

  Future<ExamQuestion> updateQuestion(
    int examId,
    int examQuestionId,
    QuestionDraft draft,
  ) async {
    final data = await _api.put<Map<String, dynamic>>(
      '/exams/$examId/questions/$examQuestionId',
      data: draft.toJson(),
    );
    return ExamQuestion.fromJson(data);
  }

  Future<void> removeQuestion(int examId, int examQuestionId) =>
      _api.delete('/exams/$examId/questions/$examQuestionId');

  // ------------------------------------------------------- join requests

  Future<List<JoinRequest>> listJoinRequests(int examId, {String? status}) async {
    final data = await _api.get<List<dynamic>>(
      '/exams/$examId/join-requests',
      query: {'status': ?status},
    );
    return data
        .map((item) => JoinRequest.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<JoinRequest> approveRequest(int requestId) async {
    final data = await _api.post<Map<String, dynamic>>('/join-requests/$requestId/approve');
    return JoinRequest.fromJson(data);
  }

  Future<JoinRequest> rejectRequest(int requestId) async {
    final data = await _api.post<Map<String, dynamic>>('/join-requests/$requestId/reject');
    return JoinRequest.fromJson(data);
  }

  /// Bulk decision, applied in one server-side transaction. [requestIds] limits it to
  /// what the teacher actually had on screen.
  Future<int> reviewAll(
    int examId, {
    required bool approve,
    List<int>? requestIds,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/exams/$examId/join-requests/${approve ? 'approve-all' : 'reject-all'}',
      data: {'request_ids': ?requestIds},
    );
    return data['updated'] as int;
  }

  // ---------------------------------------------------------------- images

  /// Uploads one image and returns the URL to store on the question or option.
  /// The server decodes the bytes before storing them, so a mislabelled file fails here.
  Future<String> uploadImage({required List<int> bytes, required String filename}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final data = await _api.post<Map<String, dynamic>>(
      '/questions/upload-image',
      data: form,
    );
    return data['url'] as String;
  }

  // --------------------------------------------------------------- results

  Future<List<TeacherResult>> examResults(int examId) async {
    final data = await _api.get<List<dynamic>>('/exams/$examId/results');
    return data
        .map((item) => TeacherResult.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Releases every unpublished result for the exam, in one server-side transaction.
  Future<int> publishResults(int examId) async {
    final data = await _api.post<Map<String, dynamic>>('/exams/$examId/results/publish');
    return data['published'] as int;
  }

  // --------------------------------------------------------------- exports

  /// Fetches a report as bytes, with the filename the server chose.
  ///
  /// Downloaded through the authenticated client rather than by opening a URL: these
  /// endpoints need a bearer token, which a plain link cannot carry.
  Future<({List<int> bytes, String filename})> _download(
    String path,
    String fallbackName,
  ) async {
    final response = await _api.download(path);
    return (
      bytes: response.bytes,
      filename: _filenameFrom(response.contentDisposition) ?? fallbackName,
    );
  }

  Future<({List<int> bytes, String filename})> examPdf(int examId) =>
      _download('/reports/exams/$examId/pdf', 'exam-$examId-results.pdf');

  Future<({List<int> bytes, String filename})> examExcel(int examId) =>
      _download('/reports/exams/$examId/excel', 'exam-$examId-results.xlsx');

  Future<({List<int> bytes, String filename})> resultPdf(int resultId) =>
      _download('/reports/results/$resultId/pdf', 'result-$resultId.pdf');

  static String? _filenameFrom(String? disposition) {
    if (disposition == null) return null;
    final match = RegExp('filename="([^"]+)"').firstMatch(disposition);
    return match?.group(1);
  }

  // ------------------------------------------------------------- analytics

  /// [passPercentage] is the university's threshold, which the platform does not know;
  /// the server echoes it back with the figures it produced.
  Future<ExamAnalytics> analytics(int examId, {double passPercentage = 40}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/exams/$examId/analytics',
      query: {'pass_percentage': passPercentage},
    );
    return ExamAnalytics.fromJson(data);
  }

  // --------------------------------------------------------------- grading

  Future<List<GradingQueueEntry>> gradingQueue(int examId) async {
    final data = await _api.get<List<dynamic>>('/exams/$examId/grading');
    return data
        .map((item) => GradingQueueEntry.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AttemptGrading> answersToMark(int attemptId) async {
    final data = await _api.get<Map<String, dynamic>>('/attempts/$attemptId/grading');
    return AttemptGrading.fromJson(data);
  }

  /// Awards marks for one written answer. The server rebuilds the result afterwards, so
  /// the returned total is authoritative.
  Future<({int awaitingMarks, double totalScore})> evaluateAnswer(
    int attemptId,
    int answerId, {
    required double marksAwarded,
    String? feedback,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/attempts/$attemptId/answers/$answerId/evaluate',
      data: {'marks_awarded': marksAwarded, 'feedback': ?feedback},
    );
    return (
      awaitingMarks: data['awaiting_marks'] as int,
      totalScore: (data['total_score'] as num).toDouble(),
    );
  }
}

/// The payload the question builder submits.
class QuestionDraft {
  const QuestionDraft({
    required this.questionText,
    required this.marks,
    required this.options,
    this.type = QuestionType.textMcq,
    this.questionImageUrl,
    this.difficulty,
    this.topic,
    this.language,
    this.timeLimitSeconds,
    this.memoryLimitMb,
  });

  final String questionText;
  final int marks;
  final List<QuestionOptionDraft> options;
  final QuestionType type;
  final String? questionImageUrl;
  final String? difficulty;
  final String? topic;

  /// CODE_ANSWER only.
  final String? language;
  final int? timeLimitSeconds;
  final int? memoryLimitMb;

  Map<String, dynamic> toJson() => {
        'type': type.wire,
        'question_text': questionText,
        'marks': marks,
        'question_image_url': ?questionImageUrl,
        'difficulty': ?difficulty,
        if (topic != null && topic!.isNotEmpty) 'topic': topic,
        'language': ?language,
        'time_limit_seconds': ?timeLimitSeconds,
        'memory_limit_mb': ?memoryLimitMb,
        'options': options.map((option) => option.toJson()).toList(),
      };
}

class QuestionOptionDraft {
  const QuestionOptionDraft({
    required this.isCorrect,
    this.optionText,
    this.optionImageUrl,
  });

  final bool isCorrect;
  final String? optionText;
  final String? optionImageUrl;

  Map<String, dynamic> toJson() => {
        'option_text': ?optionText,
        'option_image_url': ?optionImageUrl,
        'is_correct': isCorrect,
      };
}
