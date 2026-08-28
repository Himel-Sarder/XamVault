import 'package:dio/dio.dart';
import 'package:uniexam/core/api_client.dart';
import 'package:uniexam/core/exam_security.dart';
import 'package:uniexam/models/attempt.dart';
import 'package:uniexam/models/exam_result.dart';
import 'package:uniexam/models/join_request.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/models/student_exam.dart';

/// The student side of the exam API.
///
/// `/exams` returns a different shape depending on who asks — a student gets
/// [StudentExam], never the teacher's view — so this is a separate repository rather
/// than extra methods on the teacher one.
class StudentRepository {
  const StudentRepository(this._api);

  final ApiClient _api;

  Future<Paged<StudentExam>> availableExams({
    int page = 1,
    int pageSize = 50,
    bool includeClosed = false,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/exams',
      query: {'page': page, 'page_size': pageSize, 'include_closed': includeClosed},
    );
    return Paged.fromJson(data, StudentExam.fromJson);
  }

  Future<StudentExam> exam(int examId) async {
    final data = await _api.get<Map<String, dynamic>>('/exams/$examId');
    return StudentExam.fromJson(data);
  }

  Future<JoinRequest> requestToJoin(int examId) async {
    final data = await _api.post<Map<String, dynamic>>('/exams/$examId/join-request');
    return JoinRequest.fromJson(data);
  }

  Future<List<MyJoinRequest>> myRequests() async {
    final data = await _api.get<List<dynamic>>('/join-requests/mine');
    return data
        .map((item) => MyJoinRequest.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ------------------------------------------------------------- attempts

  /// Start the exam, or resume the attempt already in progress. The server decides
  /// which, so the app calls the same endpoint either way.
  Future<Attempt> startExam(int examId) async {
    final data = await _api.post<Map<String, dynamic>>('/exams/$examId/start');
    return Attempt.fromJson(data);
  }

  Future<Attempt> attempt(int attemptId) async {
    final data = await _api.get<Map<String, dynamic>>('/attempts/$attemptId');
    return Attempt.fromJson(data);
  }

  /// Returns the server's remaining seconds, which the caller uses to re-sync its
  /// countdown. A null option id clears the answer.
  Future<AnswerAck> saveAnswer(
    int attemptId, {
    required int examQuestionId,
    int? selectedOptionId,
    String? answerText,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/attempts/$attemptId/answers',
      data: {
        'exam_question_id': examQuestionId,
        'selected_option_id': selectedOptionId,
        'answer_text': answerText,
      },
    );
    return AnswerAck(
      answeredCount: data['answered_count'] as int,
      remainingSeconds: data['remaining_seconds'] as int,
    );
  }

  Future<SubmitOutcome> submit(int attemptId) async {
    final data = await _api.post<Map<String, dynamic>>('/attempts/$attemptId/submit');
    return SubmitOutcome.fromJson(data);
  }

  // ------------------------------------------------------------- security

  /// Reports what the device observed. Sent as a batch because events queue up while
  /// the device is offline, and best-effort because a failed report must never
  /// interrupt an exam in progress.
  Future<void> reportSecurityEvents(
    int attemptId,
    List<SecurityObservation> observations,
  ) async {
    if (observations.isEmpty) return;
    await _api.post<dynamic>(
      '/attempts/$attemptId/security-events',
      data: {'events': observations.map((event) => event.toJson()).toList()},
    );
  }

  // -------------------------------------------------------------- results

  Future<List<ExamResult>> myResults() async {
    final data = await _api.get<List<dynamic>>('/results');
    return data
        .map((item) => ExamResult.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// The student's own statement of result, as a PDF.
  Future<({List<int> bytes, String filename})> resultPdf(int resultId) async {
    final response = await _api.download('/reports/results/$resultId/pdf');
    final match = RegExp('filename="([^"]+)"')
        .firstMatch(response.contentDisposition ?? '');
    return (
      bytes: response.bytes,
      filename: match?.group(1) ?? 'result-$resultId.pdf',
    );
  }

  Future<ExamResult> result(int resultId) async {
    final data = await _api.get<Map<String, dynamic>>('/results/$resultId');
    return ExamResult.fromJson(data);
  }

  /// Adds one photograph of work done on paper.
  ///
  /// The three-photograph cap is the server's, and this reports whatever it says the
  /// answer now holds rather than assuming the upload landed.
  Future<AnswerAck> addAnswerPhoto(
    int attemptId, {
    required int examQuestionId,
    required List<int> bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final data = await _api.post<Map<String, dynamic>>(
      '/attempts/$attemptId/answers/$examQuestionId/photos',
      data: form,
    );
    return AnswerAck.fromJson(data);
  }

  Future<AnswerAck> removeAnswerPhoto(
    int attemptId, {
    required int examQuestionId,
    required String url,
  }) async {
    final data = await _api.deleteWithResult<Map<String, dynamic>>(
      '/attempts/$attemptId/answers/$examQuestionId/photos?url=$url',
    );
    return AnswerAck.fromJson(data);
  }
}

/// What the server confirms after saving one answer.
class AnswerAck {
  const AnswerAck({
    required this.answeredCount,
    required this.remainingSeconds,
    this.answerImageUrls = const [],
  });

  final int answeredCount;
  final int remainingSeconds;

  /// The photographs the answer now holds. The server's list rather than the client's
  /// guess, so a rejected upload cannot leave the screen showing one that never stored.
  final List<String> answerImageUrls;

  factory AnswerAck.fromJson(Map<String, dynamic> json) => AnswerAck(
        answeredCount: json['answered_count'] as int,
        remainingSeconds: json['remaining_seconds'] as int,
        answerImageUrls: (json['answer_image_urls'] as List<dynamic>? ?? const [])
            .map((item) => item as String)
            .toList(growable: false),
      );
}
