import 'dart:async';

import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/core/exam_security.dart';
import 'package:uniexam/models/analytics.dart';
import 'package:uniexam/models/attempt.dart';
import 'package:uniexam/models/auth_tokens.dart';
import 'package:uniexam/models/bank_question.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/models/enrollment.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/models/exam_result.dart';
import 'package:uniexam/models/join_request.dart';
import 'package:uniexam/models/notification.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/models/question.dart';
import 'package:uniexam/models/student_exam.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/admin_provider.dart';
import 'package:uniexam/repositories/admin_repository.dart';
import 'package:uniexam/repositories/auth_repository.dart';
import 'package:uniexam/repositories/course_repository.dart';
import 'package:uniexam/repositories/department_repository.dart';
import 'package:uniexam/repositories/exam_repository.dart';
import 'package:uniexam/repositories/notification_repository.dart';
import 'package:uniexam/repositories/question_bank_repository.dart';
import 'package:uniexam/repositories/student_repository.dart';

const demoDepartment = Department(id: 1, code: 'CSE', name: 'Computer Science & Engineering');

User teacherUser = const User(
  id: 2,
  userId: 'T1001',
  name: 'Dr Demo Teacher',
  role: UserRole.teacher,
  departmentId: 1,
  department: demoDepartment,
  teacherProfile: TeacherProfile(teacherId: 'T1001', designation: 'Lecturer'),
);

User studentUser = const User(
  id: 3,
  userId: '20261234',
  name: 'Demo Student',
  role: UserRole.student,
  departmentId: 1,
  department: demoDepartment,
  studentProfile: StudentProfile(studentId: '20261234', semester: 6, session: '2025-2026'),
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user, this.failWith});

  User? user;
  ApiException? failWith;

  int loginCalls = 0;
  int logoutCalls = 0;

  @override
  Future<AuthTokens> login({required String userId, required String password}) async {
    loginCalls++;
    final error = failWith;
    if (error != null) throw error;
    final full = user!;
    return AuthTokens(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      expiresIn: 1800,
      // The real API returns only the compact user here - no profile, no department.
      // The fake must do the same, or it hides bugs in what the app does next.
      user: User(id: full.id, userId: full.userId, name: full.name, role: full.role),
    );
  }

  @override
  Future<User> me() async {
    final current = user;
    if (current == null) {
      throw const ApiException('Not authenticated', statusCode: 401);
    }
    return current;
  }

  @override
  Future<void> logout(String refreshToken) async => logoutCalls++;

  /// Every change the screen actually sent, so a test can prove nothing went out
  /// when the form should have caught the problem itself.
  final List<(String, String)> passwordChanges = [];

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordChanges.add((currentPassword, newPassword));
  }
}

class FakeCourseRepository implements CourseRepository {
  // Copied, not shared: `create` appends, and a const literal cannot be added to.
  FakeCourseRepository({List<Course>? courses})
      : courses = [...(courses ?? _defaultCourses)];

  static const _defaultCourses = [
    Course(
      id: 1,
      courseCode: 'CSE-301',
      courseName: 'Database Management System',
      createdBy: 2,
      session: '2025-2026',
    ),
  ];

  final List<Course> courses;

  @override
  Future<Paged<Course>> list({int page = 1, int pageSize = 20, bool activeOnly = false}) async {
    return Paged<Course>(
      items: courses,
      total: courses.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<Course> get(int id) async => courses.firstWhere((course) => course.id == id);

  // ------------------------------------------------------------- writes

  final List<Course> created = [];
  final List<({int id, String? name, bool? isActive})> updated = [];

  @override
  Future<Course> create({
    required String courseCode,
    required String courseName,
    int? departmentId,
    int? semester,
    String? session,
  }) async {
    final course = Course(
      id: courses.length + 100,
      courseCode: courseCode,
      courseName: courseName,
      createdBy: 2,
      departmentId: departmentId,
      semester: semester,
      session: session,
    );
    created.add(course);
    courses.add(course);
    return course;
  }

  @override
  Future<Course> update(
    int id, {
    String? courseName,
    int? departmentId,
    int? semester,
    String? session,
    bool? isActive,
  }) async {
    updated.add((id: id, name: courseName, isActive: isActive));
    return get(id);
  }

  // ---------------------------------------------------------- enrolment

  List<Enrollment> roll = [];
  final List<String> enrolled = [];
  final List<List<String>> bulkBatches = [];
  final List<int> removed = [];

  /// Set to make the next bulk call report these as skipped.
  List<SkippedEnrolment> nextSkipped = const [];

  @override
  Future<List<Enrollment>> enrollments(int courseId) async => roll;

  @override
  Future<Enrollment> enroll(int courseId, String studentUserId) async {
    enrolled.add(studentUserId);
    final entry = Enrollment(
      id: roll.length + 1,
      courseId: courseId,
      studentId: roll.length + 50,
      student: UserSummary(
        id: roll.length + 50,
        userId: studentUserId,
        name: 'Student $studentUserId',
        role: UserRole.student,
      ),
    );
    roll = [...roll, entry];
    return entry;
  }

  @override
  Future<BulkEnrolmentResult> enrollBulk(int courseId, List<String> studentUserIds) async {
    bulkBatches.add(studentUserIds);
    final skippedIds = nextSkipped.map((s) => s.studentUserId).toSet();
    final took = studentUserIds.where((id) => !skippedIds.contains(id)).toList();
    for (final id in took) {
      await enroll(courseId, id);
    }
    return BulkEnrolmentResult(
      enrolled: roll
          .where((e) => took.contains(e.student?.userId))
          .map((e) => e.student!)
          .toList(growable: false),
      skipped: nextSkipped,
    );
  }

  @override
  Future<void> unenroll(int courseId, int studentId) async {
    removed.add(studentId);
    roll = roll.where((e) => e.studentId != studentId).toList();
  }
}

class FakeDepartmentRepository implements DepartmentRepository {
  FakeDepartmentRepository({List<Department>? departments})
      : departments = departments ??
            [
              const Department(id: 1, code: 'CSE', name: 'Computer Science'),
              const Department(id: 2, code: 'EEE', name: 'Electrical Engineering'),
            ];

  final List<Department> departments;
  final List<({String code, String name})> created = [];
  final List<({int id, String? name, bool? isActive})> updated = [];

  @override
  Future<List<Department>> list() async => departments;

  @override
  Future<Department> create({required String code, required String name}) async {
    created.add((code: code, name: name));
    final department = Department(id: departments.length + 10, code: code, name: name);
    departments.add(department);
    return department;
  }

  @override
  Future<Department> update(int id, {String? name, bool? isActive}) async {
    updated.add((id: id, name: name, isActive: isActive));
    return departments.firstWhere((d) => d.id == id);
  }
}

/// A department list that will not load, for the case where the picker fails but the
/// form must still be usable.
class FailingDepartmentRepository implements DepartmentRepository {
  @override
  Future<List<Department>> list() async =>
      throw const ApiException('Departments are unavailable');

  @override
  Future<Department> create({required String code, required String name}) async =>
      throw const ApiException('Departments are unavailable');

  @override
  Future<Department> update(int id, {String? name, bool? isActive}) async =>
      throw const ApiException('Departments are unavailable');
}

class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({List<User>? users}) : directory = users ?? [];

  /// Not named `users`: the repository method is called that.
  final List<User> directory;
  final List<({String userId, UserRole role})> created = [];
  final List<({int id, String? name, bool? isActive})> updated = [];
  UserFilter? lastFilter;

  @override
  Future<Paged<User>> users({
    int page = 1,
    int pageSize = 20,
    UserRole? role,
    String? search,
  }) async {
    lastFilter = (role: role, search: search);
    final matched = directory.where((u) {
      if (role != null && u.role != role) return false;
      if (search != null && search.isNotEmpty) {
        final needle = search.toLowerCase();
        return u.name.toLowerCase().contains(needle) ||
            u.userId.toLowerCase().contains(needle);
      }
      return true;
    }).toList(growable: false);
    return Paged<User>(
      items: matched,
      total: matched.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<User> user(int id) async => directory.firstWhere((u) => u.id == id);

  @override
  Future<User> createUser({
    required String userId,
    required String password,
    required String name,
    required UserRole role,
    String? email,
    int? departmentId,
    String? studentId,
    int? semester,
    String? session,
    String? teacherId,
    String? designation,
  }) async {
    created.add((userId: userId, role: role));
    final user = User(
      id: directory.length + 200,
      userId: userId,
      name: name,
      role: role,
      email: email,
      departmentId: departmentId,
    );
    directory.add(user);
    return user;
  }

  @override
  Future<User> updateUser(
    int id, {
    String? name,
    String? email,
    int? departmentId,
    bool? isActive,
  }) async {
    updated.add((id: id, name: name, isActive: isActive));
    return user(id);
  }
}

// ------------------------------------------------------------------ exams

Exam buildExam({
  int id = 10,
  int courseId = 1,
  String title = 'Mid Term Quiz',
  ExamStatus status = ExamStatus.draft,
  int questionCount = 0,
  int totalMarks = 0,
  DateTime? startAt,
  int durationMinutes = 30,
  ExamSettings settings = const ExamSettings(),
}) {
  return Exam(
    id: id,
    courseId: courseId,
    teacherId: 2,
    title: title,
    durationMinutes: durationMinutes,
    totalMarks: totalMarks,
    status: status,
    questionCount: questionCount,
    startAt: startAt ?? DateTime.now().add(const Duration(days: 1)),
    settings: settings,
  );
}

ExamQuestion buildExamQuestion({
  int id = 100,
  int examId = 10,
  int displayOrder = 0,
  int marks = 1,
  bool isFrozen = false,
  String text = 'What is normalization?',
  int correctIndex = 1,
  List<String> options = const ['Option A', 'Option B', 'Option C', 'Option D'],
}) {
  return ExamQuestion(
    id: id,
    examId: examId,
    displayOrder: displayOrder,
    marks: marks,
    isFrozen: isFrozen,
    question: Question(
      id: id,
      type: QuestionType.textMcq,
      questionText: text,
      marks: marks,
      options: [
        for (var index = 0; index < options.length; index++)
          QuestionOption(
            id: index + 1,
            displayOrder: index,
            isCorrect: index == correctIndex,
            optionText: options[index],
          ),
      ],
    ),
  );
}

class FakeExamRepository implements ExamRepository {
  FakeExamRepository({
    List<Exam>? exams,
    List<ExamQuestion>? questions,
    this.publishCheckResult = const PublishCheck(canPublish: true, issues: []),
    this.failWith,
  })  : exams = exams ?? [buildExam()],
        questions = questions ?? [];

  final List<Exam> exams;
  final List<ExamQuestion> questions;
  PublishCheck publishCheckResult;
  ApiException? failWith;

  final List<QuestionDraft> addedQuestions = [];
  final List<QuestionDraft> updatedQuestions = [];
  final List<Map<String, dynamic>> createdExams = [];
  int publishCalls = 0;
  int removeCalls = 0;

  void _maybeFail() {
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<Paged<Exam>> list({int? courseId, int page = 1, int pageSize = 50}) async {
    _maybeFail();
    final items = courseId == null
        ? exams
        : exams.where((exam) => exam.courseId == courseId).toList();
    return Paged<Exam>(items: items, total: items.length, page: page, pageSize: pageSize);
  }

  @override
  Future<Exam> get(int examId) async {
    _maybeFail();
    return exams.firstWhere((exam) => exam.id == examId);
  }

  @override
  Future<Exam> create({
    required int courseId,
    required String title,
    required int durationMinutes,
    String? description,
    DateTime? startAt,
    ExamSettings? settings,
  }) async {
    _maybeFail();
    createdExams.add({
      'course_id': courseId,
      'title': title,
      'duration_minutes': durationMinutes,
      'description': description,
      'start_at': startAt,
      'settings': settings,
    });
    final created = buildExam(
      id: 99,
      courseId: courseId,
      title: title,
      durationMinutes: durationMinutes,
      startAt: startAt,
      settings: settings ?? const ExamSettings(),
    );
    exams.add(created);
    return created;
  }

  @override
  Future<Exam> update(
    int examId, {
    String? title,
    String? description,
    DateTime? startAt,
    int? durationMinutes,
  }) async {
    _maybeFail();
    return get(examId);
  }

  @override
  Future<Exam> updateSettings(int examId, ExamSettings settings) async {
    _maybeFail();
    return get(examId);
  }

  @override
  Future<void> delete(int examId) async => _maybeFail();

  @override
  Future<PublishCheck> publishCheck(int examId) async {
    _maybeFail();
    return publishCheckResult;
  }

  @override
  Future<Exam> publish(int examId) async {
    _maybeFail();
    publishCalls++;
    return get(examId);
  }

  @override
  Future<List<ExamQuestion>> listQuestions(int examId) async {
    _maybeFail();
    return questions.where((item) => item.examId == examId).toList();
  }

  @override
  Future<ExamQuestion> addQuestion(int examId, QuestionDraft draft) async {
    _maybeFail();
    addedQuestions.add(draft);
    return buildExamQuestion(examId: examId, text: draft.questionText, marks: draft.marks);
  }

  @override
  Future<ExamQuestion> updateQuestion(
    int examId,
    int examQuestionId,
    QuestionDraft draft,
  ) async {
    _maybeFail();
    updatedQuestions.add(draft);
    return buildExamQuestion(id: examQuestionId, examId: examId, text: draft.questionText);
  }

  @override
  Future<void> removeQuestion(int examId, int examQuestionId) async {
    _maybeFail();
    removeCalls++;
  }

  // ---------------------------------------------------------- join requests

  List<JoinRequest> joinRequests = [];
  final List<(int, bool)> reviewed = [];
  final List<(bool, List<int>?)> bulkReviews = [];

  @override
  Future<List<JoinRequest>> listJoinRequests(int examId, {String? status}) async {
    _maybeFail();
    final items = joinRequests.where((request) => request.examId == examId);
    if (status == null) return items.toList();
    return items.where((request) => request.status.wire == status).toList();
  }

  @override
  Future<JoinRequest> approveRequest(int requestId) async {
    _maybeFail();
    reviewed.add((requestId, true));
    return _decide(requestId, JoinRequestStatus.approved);
  }

  @override
  Future<JoinRequest> rejectRequest(int requestId) async {
    _maybeFail();
    reviewed.add((requestId, false));
    return _decide(requestId, JoinRequestStatus.rejected);
  }

  @override
  Future<int> reviewAll(int examId, {required bool approve, List<int>? requestIds}) async {
    _maybeFail();
    bulkReviews.add((approve, requestIds));
    final target = approve ? JoinRequestStatus.approved : JoinRequestStatus.rejected;
    var updated = 0;
    for (final request in [...joinRequests]) {
      final selected = requestIds == null || requestIds.contains(request.id);
      if (request.examId == examId && request.isPending && selected) {
        _decide(request.id, target);
        updated++;
      }
    }
    return updated;
  }

  // ---------------------------------------------------------------- images

  final List<String> uploadedFilenames = [];

  @override
  Future<String> uploadImage({required List<int> bytes, required String filename}) async {
    _maybeFail();
    uploadedFilenames.add(filename);
    return '/uploads/${uploadedFilenames.length}.png';
  }

  // --------------------------------------------------------------- results

  List<TeacherResult> results = [];
  int publishResultsCalls = 0;

  @override
  Future<List<TeacherResult>> examResults(int examId) async {
    _maybeFail();
    return results.where((result) => result.examId == examId).toList();
  }

  @override
  Future<int> publishResults(int examId) async {
    _maybeFail();
    publishResultsCalls++;
    final pending = results.where((result) => !result.isPublished).toList();
    results = [
      for (final result in results)
        result.isPublished ? result : _publishedCopy(result),
    ];
    return pending.length;
  }

  // --------------------------------------------------------------- exports

  final List<String> exported = [];

  /// Separate from [failWith] so a test can fail an export without also breaking the
  /// initial load of the screen doing the exporting.
  ApiException? failExports;

  void _maybeFailExport() {
    final error = failExports;
    if (error != null) throw error;
  }

  @override
  Future<({List<int> bytes, String filename})> examPdf(int examId) async {
    _maybeFailExport();
    exported.add('pdf');
    return (bytes: <int>[37, 80, 68, 70], filename: 'CSE-301-results.pdf');
  }

  @override
  Future<({List<int> bytes, String filename})> examExcel(int examId) async {
    _maybeFailExport();
    exported.add('excel');
    return (bytes: <int>[80, 75, 3, 4], filename: 'CSE-301-results.xlsx');
  }

  @override
  Future<({List<int> bytes, String filename})> resultPdf(int resultId) async {
    _maybeFailExport();
    exported.add('result-pdf');
    return (bytes: <int>[37, 80, 68, 70], filename: 'CSE-301-result.pdf');
  }

  // ------------------------------------------------------------- analytics

  ExamAnalytics? analyticsResult;
  final List<double> analyticsThresholds = [];

  @override
  Future<ExamAnalytics> analytics(int examId, {double passPercentage = 40}) async {
    _maybeFail();
    analyticsThresholds.add(passPercentage);
    return analyticsResult ?? buildAnalytics(passPercentage: passPercentage);
  }

  // --------------------------------------------------------------- grading

  List<GradingQueueEntry> queue = [];
  AttemptGrading? grading;
  final List<({int answerId, double marks, String? feedback})> awarded = [];

  @override
  Future<List<GradingQueueEntry>> gradingQueue(int examId) async {
    _maybeFail();
    return queue;
  }

  @override
  Future<AttemptGrading> answersToMark(int attemptId) async {
    _maybeFail();
    return grading ?? buildAttemptGrading(attemptId: attemptId);
  }

  @override
  Future<({int awaitingMarks, double totalScore})> evaluateAnswer(
    int attemptId,
    int answerId, {
    required double marksAwarded,
    String? feedback,
  }) async {
    _maybeFail();
    awarded.add((answerId: answerId, marks: marksAwarded, feedback: feedback));
    return (awaitingMarks: 0, totalScore: marksAwarded);
  }

  TeacherResult _publishedCopy(TeacherResult result) => TeacherResult(
        id: result.id,
        examId: result.examId,
        attemptId: result.attemptId,
        studentName: result.studentName,
        studentNumber: result.studentNumber,
        scores: result.scores,
        totalScore: result.totalScore,
        totalMarks: result.totalMarks,
        percentage: result.percentage,
        status: 'published',
        submittedAt: result.submittedAt,
        publishedAt: DateTime(2026, 8, 24),
      );

  JoinRequest _decide(int requestId, JoinRequestStatus status) {
    final index = joinRequests.indexWhere((request) => request.id == requestId);
    final existing = joinRequests[index];
    final updated = JoinRequest(
      id: existing.id,
      examId: existing.examId,
      status: status,
      requestedAt: existing.requestedAt,
      student: existing.student,
      reviewedAt: DateTime(2026, 8, 24),
      reviewedBy: 2,
    );
    joinRequests[index] = updated;
    return updated;
  }
}

// ------------------------------------------------------------- student side

StudentExam buildStudentExam({
  int id = 10,
  int courseId = 1,
  String courseCode = 'CSE-301',
  String title = 'Mid Term Quiz',
  ExamAvailability availability = ExamAvailability.upcoming,
  JoinRequestStatus joinRequestStatus = JoinRequestStatus.none,
  bool? canRequestJoin,
  int questionCount = 4,
  int totalMarks = 20,
  DateTime? startAt,
  bool secureMode = true,
}) {
  return StudentExam(
    id: id,
    courseId: courseId,
    courseCode: courseCode,
    courseName: 'Database Management System',
    title: title,
    durationMinutes: 30,
    totalMarks: totalMarks,
    questionCount: questionCount,
    availability: availability,
    joinRequestStatus: joinRequestStatus,
    canRequestJoin: canRequestJoin ??
        (availability != ExamAvailability.closed &&
            (joinRequestStatus == JoinRequestStatus.none ||
                joinRequestStatus == JoinRequestStatus.rejected)),
    settings: const StudentExamSettings(
      secureMode: true,
      allowBackNavigation: true,
      maxAttempts: 1,
    ),
    startAt: startAt ?? DateTime.now().add(const Duration(days: 1)),
  );
}

JoinRequest buildJoinRequest({
  int id = 500,
  int examId = 10,
  JoinRequestStatus status = JoinRequestStatus.pending,
  String name = 'Demo Student',
  String userId = '20261234',
}) {
  return JoinRequest(
    id: id,
    examId: examId,
    status: status,
    requestedAt: DateTime(2026, 8, 23, 10, 30),
    student: JoinRequestStudent(
      id: 3,
      userId: userId,
      name: name,
      studentNumber: userId,
    ),
  );
}


Attempt buildAttempt({
  int id = 900,
  int examId = 10,
  String examTitle = 'Mid Term Quiz',
  AttemptStatus status = AttemptStatus.active,
  int remainingSeconds = 1800,
  bool allowBackNavigation = true,
  int questionCount = 3,
  bool secureMode = false,
  Map<int, int?> answers = const {},
  /// Index -> written question type, for the questions that are not multiple choice.
  Map<int, String> writtenTypes = const {},
}) {
  final questions = [
    for (var index = 0; index < questionCount; index++)
      if (writtenTypes.containsKey(index))
        AttemptQuestion(
          examQuestionId: 100 + index,
          position: index + 1,
          type: writtenTypes[index]!,
          questionText: 'Question ${index + 1}: explain in your own words.',
          marks: 10,
          options: const [],
          language: writtenTypes[index] == 'CODE_ANSWER' ? 'cpp' : null,
          timeLimitSeconds: writtenTypes[index] == 'CODE_ANSWER' ? 2 : null,
          memoryLimitMb: writtenTypes[index] == 'CODE_ANSWER' ? 256 : null,
        )
      else
        AttemptQuestion(
          examQuestionId: 100 + index,
          position: index + 1,
          type: 'TEXT_MCQ',
          questionText: 'Question ${index + 1}: what is normalization?',
          marks: 5,
          selectedOptionId: answers[100 + index],
          options: [
            for (var option = 0; option < 4; option++)
              AttemptOption(
                id: (100 + index) * 10 + option,
                optionText: 'Option ${String.fromCharCode(65 + option)} for Q${index + 1}',
              ),
          ],
        ),
  ];
  return Attempt(
    id: id,
    examId: examId,
    examTitle: examTitle,
    courseCode: 'CSE-301',
    status: status,
    startedAt: DateTime(2026, 8, 24, 10),
    expiresAt: DateTime(2026, 8, 24, 10, 30),
    remainingSeconds: remainingSeconds,
    durationMinutes: 30,
    totalMarks: 5 * questionCount,
    allowBackNavigation: allowBackNavigation,
    secureMode: secureMode,
    questions: questions,
    answeredCount: questions.where((q) => q.isAnswered).length,
    totalQuestions: questions.length,
  );
}

AnswerToMark buildAnswerToMark({
  int answerId = 800,
  int examQuestionId = 101,
  int position = 2,
  String type = 'SHORT_ANSWER',
  String questionText = 'Explain the difference between TCP and UDP.',
  int maxMarks = 10,
  String status = 'pending',
  String? language,
  String? answerText = 'TCP is reliable and connection-oriented; UDP is neither.',
  double? marksAwarded,
  String? feedback,
}) {
  return AnswerToMark(
    answerId: answerId,
    examQuestionId: examQuestionId,
    position: position,
    type: type,
    questionText: questionText,
    maxMarks: maxMarks,
    status: status,
    language: language,
    answerText: answerText,
    marksAwarded: marksAwarded,
    feedback: feedback,
  );
}

AttemptGrading buildAttemptGrading({
  int attemptId = 900,
  String studentName = 'Demo Student',
  int? awaitingMarks,
  List<AnswerToMark>? answers,
}) {
  final items = answers ?? [buildAnswerToMark()];
  return AttemptGrading(
    attemptId: attemptId,
    examTitle: 'Mixed Paper',
    studentName: studentName,
    awaitingMarks: awaitingMarks ??
        items.where((answer) => answer.status == 'pending').length,
    answers: items,
    submittedAt: DateTime(2026, 8, 24, 10, 20),
  );
}

ExamAnalytics buildAnalytics({
  int examId = 10,
  int approved = 3,
  int submitted = 3,
  int inProgress = 0,
  int absent = 0,
  ScoreSummary? scores,
  double passPercentage = 40,
  int passed = 2,
  int failed = 1,
  double? passRate = 66.7,
  List<DistributionBucket>? distribution,
  List<QuestionAnalytics>? questions,
}) {
  return ExamAnalytics(
    examId: examId,
    examTitle: 'Analytics Paper',
    courseCode: 'CSE-301',
    totalMarks: 30,
    cohort: CohortCounts(
      approved: approved,
      submitted: submitted,
      inProgress: inProgress,
      absent: absent,
    ),
    scores: scores ??
        const ScoreSummary(average: 33.3, highest: 66.7, lowest: 0, median: 33.3),
    passPercentage: passPercentage,
    passed: passed,
    failed: failed,
    passRate: passRate,
    distribution: distribution ??
        const [
          DistributionBucket(label: '0-20%', count: 1),
          DistributionBucket(label: '21-40%', count: 1),
          DistributionBucket(label: '41-60%', count: 0),
          DistributionBucket(label: '61-80%', count: 1),
          DistributionBucket(label: '81-100%', count: 0),
        ],
    questions: questions ??
        const [
          QuestionAnalytics(
            examQuestionId: 101,
            position: 1,
            type: 'TEXT_MCQ',
            questionText: 'Q1 what is normalization?',
            marks: 10,
            isAutoMarked: true,
            answered: 2,
            skipped: 1,
            awaitingMarks: 0,
            correct: 2,
            wrong: 0,
            correctRate: 66.7,
          ),
          QuestionAnalytics(
            examQuestionId: 103,
            position: 3,
            type: 'SHORT_ANSWER',
            questionText: 'Q3 explain',
            marks: 10,
            isAutoMarked: false,
            answered: 2,
            skipped: 1,
            awaitingMarks: 2,
          ),
        ],
  );
}

GradingQueueEntry buildGradingEntry({
  int attemptId = 900,
  String studentName = 'Demo Student',
  String studentNumber = '20261234',
  int awaitingMarks = 2,
  double totalScore = 5,
  int totalMarks = 25,
}) {
  return GradingQueueEntry(
    attemptId: attemptId,
    studentName: studentName,
    studentNumber: studentNumber,
    awaitingMarks: awaitingMarks,
    totalScore: totalScore,
    totalMarks: totalMarks,
    submittedAt: DateTime(2026, 8, 24, 10, 20),
  );
}

TeacherResult buildTeacherResult({
  int id = 700,
  int examId = 10,
  String studentName = 'Demo Student',
  String studentNumber = '20261234',
  double totalScore = 15,
  int totalMarks = 15,
  double percentage = 100,
  String status = 'pending',
}) {
  return TeacherResult(
    id: id,
    examId: examId,
    attemptId: 900,
    studentName: studentName,
    studentNumber: studentNumber,
    scores: ScoreBreakdown(mcq: totalScore, shortAnswer: 0, code: 0),
    totalScore: totalScore,
    totalMarks: totalMarks,
    percentage: percentage,
    status: status,
    submittedAt: DateTime(2026, 8, 24, 10, 20),
  );
}

ExamResult buildExamResult({
  int id = 700,
  String examTitle = 'Mid Term Quiz',
  double totalScore = 15,
  int totalMarks = 15,
  double percentage = 100,
  String status = 'published',
}) {
  return ExamResult(
    id: id,
    examId: 10,
    examTitle: examTitle,
    courseCode: 'CSE-301',
    attemptId: 900,
    scores: ScoreBreakdown(mcq: totalScore, shortAnswer: 0, code: 0),
    totalScore: totalScore,
    totalMarks: totalMarks,
    percentage: percentage,
    status: status,
    submittedAt: DateTime(2026, 8, 24, 10, 20),
    publishedAt: DateTime(2026, 8, 24, 11),
  );
}

class FakeStudentRepository implements StudentRepository {
  FakeStudentRepository({List<StudentExam>? exams, List<MyJoinRequest>? requests, this.failWith})
      : exams = exams ?? [buildStudentExam()],
        requests = requests ?? [];

  final List<StudentExam> exams;
  final List<MyJoinRequest> requests;
  ApiException? failWith;

  final List<int> joinRequestsSent = [];

  void _maybeFail() {
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<Paged<StudentExam>> availableExams({
    int page = 1,
    int pageSize = 50,
    bool includeClosed = false,
  }) async {
    _maybeFail();
    final items = includeClosed
        ? exams
        : exams.where((exam) => exam.availability != ExamAvailability.closed).toList();
    return Paged<StudentExam>(
      items: items,
      total: items.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<StudentExam> exam(int examId) async {
    _maybeFail();
    return exams.firstWhere((item) => item.id == examId);
  }

  @override
  Future<JoinRequest> requestToJoin(int examId) async {
    _maybeFail();
    joinRequestsSent.add(examId);
    return buildJoinRequest(examId: examId);
  }

  @override
  Future<List<MyJoinRequest>> myRequests() async {
    _maybeFail();
    return requests;
  }

  // -------------------------------------------------------------- attempts

  Attempt? currentAttempt;
  List<ExamResult> results = [];

  final List<int> startedExams = [];
  final List<({int questionId, int? optionId})> savedAnswers = [];
  int submitCalls = 0;
  int serverRemainingSeconds = 1800;

  @override
  Future<Attempt> startExam(int examId) async {
    _maybeFail();
    startedExams.add(examId);
    return currentAttempt ??= buildAttempt(examId: examId);
  }

  @override
  Future<Attempt> attempt(int attemptId) async {
    _maybeFail();
    return currentAttempt ??= buildAttempt(id: attemptId);
  }

  final List<({int questionId, String? text})> savedTexts = [];

  @override
  Future<AnswerAck> saveAnswer(
    int attemptId, {
    required int examQuestionId,
    int? selectedOptionId,
    String? answerText,
  }) async {
    _maybeFail();
    if (answerText != null) {
      savedTexts.add((questionId: examQuestionId, text: answerText));
    } else {
      savedAnswers.add((questionId: examQuestionId, optionId: selectedOptionId));
    }
    final attempt = currentAttempt!;
    final updated = attempt.questions
        .map((question) => question.examQuestionId == examQuestionId
            ? question.copyWith(
                selectedOptionId: selectedOptionId,
                clearSelection: selectedOptionId == null,
                answerText: answerText,
                clearText: answerText != null && answerText.isEmpty,
              )
            : question)
        .toList();
    final answered = updated.where((question) => question.isAnswered).length;
    currentAttempt = attempt.copyWith(questions: updated, answeredCount: answered);
    return AnswerAck(
      answeredCount: answered,
      remainingSeconds: serverRemainingSeconds,
    );
  }

  @override
  Future<SubmitOutcome> submit(int attemptId) async {
    _maybeFail();
    submitCalls++;
    final attempt = currentAttempt!;
    return SubmitOutcome(
      attemptId: attemptId,
      status: AttemptStatus.submitted,
      submittedAt: DateTime(2026, 8, 24, 10, 20),
      answeredCount: attempt.answeredCount,
      totalQuestions: attempt.totalQuestions,
    );
  }

  final List<SecurityObservation> reportedEvents = [];
  bool failSecurityReports = false;

  @override
  Future<void> reportSecurityEvents(
    int attemptId,
    List<SecurityObservation> observations,
  ) async {
    if (failSecurityReports) {
      throw const ApiException('Reporting failed', statusCode: 500);
    }
    reportedEvents.addAll(observations);
  }

  @override
  Future<List<ExamResult>> myResults() async {
    _maybeFail();
    return results;
  }

  @override
  Future<ExamResult> result(int resultId) async {
    _maybeFail();
    return results.firstWhere((item) => item.id == resultId);
  }

  final List<int> exportedResults = [];

  @override
  Future<({List<int> bytes, String filename})> resultPdf(int resultId) async {
    _maybeFail();
    exportedResults.add(resultId);
    return (bytes: <int>[37, 80, 68, 70], filename: 'CSE-301-result.pdf');
  }
}


/// Stands in for the Android bridge so the exam screen can be driven in tests.
class FakeExamSecurity implements ExamSecurity {
  FakeExamSecurity({
    this.supported = true,
    LockdownStatus? status,
  }) : status = status ??
            const LockdownStatus(
              secureFlag: true,
              immersive: true,
              lockTask: true,
              lockTaskIsPinning: true,
              detail: 'Screen pinned; the student can still exit',
            );

  final bool supported;
  LockdownStatus status;

  final _controller = StreamController<SecurityObservation>.broadcast();
  int enterCalls = 0;
  int exitCalls = 0;
  bool listening = false;

  /// Push an observation as if Android had reported it.
  void emit(SecurityObservation observation) => _controller.add(observation);

  @override
  bool get isSupported => supported;

  @override
  Stream<SecurityObservation> get observations => _controller.stream;

  @override
  void startListening() => listening = true;

  @override
  Future<LockdownStatus> enter() async {
    enterCalls++;
    return supported
        ? status
        : const LockdownStatus.unavailable(
            'Device lockdown is only available in the Android app');
  }

  @override
  Future<void> exit() async => exitCalls++;

  @override
  void dispose() => _controller.close();
}


BankQuestion buildBankQuestion({
  int id = 300,
  QuestionType type = QuestionType.textMcq,
  String questionText = 'What is normalization?',
  int marks = 5,
  String? topic = 'Databases',
  String? difficulty = 'medium',
  int usedInExams = 0,
  bool usedInPublished = false,
  String? language,
}) {
  return BankQuestion(
    id: id,
    type: type,
    questionText: questionText,
    marks: marks,
    topic: topic,
    difficulty: difficulty,
    language: language,
    usedInExams: usedInExams,
    usedInPublished: usedInPublished,
    options: const [
      QuestionOption(id: 1, displayOrder: 0, isCorrect: true, optionText: 'Removing redundancy'),
      QuestionOption(id: 2, displayOrder: 1, isCorrect: false, optionText: 'Adding redundancy'),
    ],
  );
}

class FakeQuestionBankRepository implements QuestionBankRepository {
  FakeQuestionBankRepository({List<BankQuestion>? questions, List<String>? topics})
      : questions = questions ?? [buildBankQuestion()],
        availableTopics = topics ?? const ['Databases', 'Networks'];

  final List<BankQuestion> questions;
  final List<String> availableTopics;
  ApiException? failWith;

  /// The filter the screen last asked for — the assertion target for filter tests.
  BankFilterCall? lastFilter;
  final List<int> deleted = [];
  final List<({int examId, List<int> questionIds})> attached = [];

  void _maybeFail() {
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<Paged<BankQuestion>> list({
    QuestionType? type,
    String? difficulty,
    String? topic,
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    _maybeFail();
    lastFilter = (type: type, difficulty: difficulty, topic: topic, search: search);
    // Filtering is the server's job; the fake returns what it was given so a test can
    // assert on the request rather than on a reimplementation of the query.
    return Paged<BankQuestion>(
      items: questions,
      total: questions.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<String>> topics() async {
    _maybeFail();
    return availableTopics;
  }

  @override
  Future<BankQuestion> create(QuestionDraft draft) async {
    _maybeFail();
    final created = buildBankQuestion(
      id: 900 + questions.length,
      questionText: draft.questionText,
      marks: draft.marks,
    );
    questions.add(created);
    return created;
  }

  @override
  Future<BankQuestion> update(int questionId, QuestionDraft draft) async {
    _maybeFail();
    return buildBankQuestion(id: questionId, questionText: draft.questionText);
  }

  @override
  Future<void> delete(int questionId) async {
    _maybeFail();
    deleted.add(questionId);
    questions.removeWhere((question) => question.id == questionId);
  }

  @override
  Future<int> attachToExam(int examId, List<int> questionIds) async {
    _maybeFail();
    attached.add((examId: examId, questionIds: questionIds));
    return questionIds.length;
  }
}

typedef BankFilterCall = ({
  QuestionType? type,
  String? difficulty,
  String? topic,
  String? search,
});


AppNotification buildNotification({
  int id = 500,
  NotificationCategory category = NotificationCategory.examPublished,
  String title = 'New exam: Mid Term Quiz',
  String body = 'CSE-301 — 30 minutes, 20 marks.',
  bool isRead = false,
  int? examId = 10,
}) {
  return AppNotification(
    id: id,
    category: category,
    title: title,
    body: body,
    isRead: isRead,
    createdAt: DateTime(2026, 8, 24, 9, 15),
    payload: examId == null ? null : {'exam_id': examId},
  );
}

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({List<AppNotification>? notifications})
      : notifications = notifications ?? [buildNotification()];

  final List<AppNotification> notifications;
  ApiException? failWith;

  final List<int> readIds = [];
  int markAllCalls = 0;
  bool? lastUnreadOnly;

  void _maybeFail() {
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<Paged<AppNotification>> list({
    bool unreadOnly = false,
    int page = 1,
    int pageSize = 50,
  }) async {
    _maybeFail();
    lastUnreadOnly = unreadOnly;
    // Filtering is the server's job, but this one is cheap to mirror and makes the
    // unread-filter test assert on what the user actually sees.
    final items = unreadOnly
        ? notifications.where((item) => !item.isRead).toList()
        : notifications;
    return Paged<AppNotification>(
      items: items,
      total: items.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<int> unreadCount() async {
    _maybeFail();
    return notifications.where((item) => !item.isRead).length;
  }

  @override
  Future<AppNotification> markRead(int notificationId) async {
    _maybeFail();
    readIds.add(notificationId);
    final index = notifications.indexWhere((item) => item.id == notificationId);
    final updated = notifications[index].copyWith(
      isRead: true,
      readAt: DateTime(2026, 8, 24, 10),
    );
    notifications[index] = updated;
    return updated;
  }

  @override
  Future<int> markAllRead() async {
    _maybeFail();
    markAllCalls++;
    final unread = notifications.where((item) => !item.isRead).length;
    for (var index = 0; index < notifications.length; index++) {
      notifications[index] = notifications[index].copyWith(
        isRead: true,
        readAt: DateTime(2026, 8, 24, 10),
      );
    }
    return unread;
  }
}
