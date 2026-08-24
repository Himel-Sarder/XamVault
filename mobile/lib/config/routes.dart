import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';

/// Route paths, in one place so nothing is spelled by hand at a call site.
class Routes {
  const Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const profile = '/profile';

  /// Shared by every role — what a tap leads to depends on who is reading.
  static const notifications = '/notifications';

  static const teacherHome = '/teacher';
  static const teacherCourses = '/teacher/courses';

  static const teacherQuestionBank = '/teacher/question-bank';

  static String teacherCourse(int courseId) => '/teacher/courses/$courseId';
  static String teacherExamCreate(int courseId) => '/teacher/courses/$courseId/exams/new';
  static String teacherExam(int examId) => '/teacher/exams/$examId';
  static String teacherExamEdit(int examId) => '/teacher/exams/$examId/edit';
  static String teacherQuestionNew(int examId) => '/teacher/exams/$examId/questions/new';
  static String teacherExamBankPicker(int examId) => '/teacher/exams/$examId/questions/bank';
  static String teacherQuestionEdit(int examId, int questionId) =>
      '/teacher/exams/$examId/questions/$questionId';

  static const studentHome = '/student';
  static const studentCourses = '/student/courses';
  static const studentExams = '/student/exams';
  static const studentRequests = '/student/requests';
  static const studentResults = '/student/results';

  static String studentAttempt(int attemptId) => '/student/attempt/$attemptId';

  static String studentExam(int examId) => '/student/exams/$examId';

  static String teacherExamRequests(int examId) => '/teacher/exams/$examId/requests';
  static String teacherExamResults(int examId) => '/teacher/exams/$examId/results';
  static String teacherExamGrading(int examId) => '/teacher/exams/$examId/grading';
  static String teacherExamAnalytics(int examId) => '/teacher/exams/$examId/analytics';
  static String teacherAttemptGrading(int examId, int attemptId) =>
      '/teacher/exams/$examId/grading/$attemptId';

  static const adminHome = '/admin';

  static String homeFor(UserRole role) => switch (role) {
        UserRole.teacher => teacherHome,
        UserRole.student => studentHome,
        UserRole.admin => adminHome,
      };

  /// The path prefix a role owns. Used to keep one role out of another's screens.
  static String prefixFor(UserRole role) => homeFor(role);
}

/// Pure routing policy, kept out of GoRouter so it can be unit-tested directly.
///
/// Returns the path to redirect to, or `null` to stay put.
String? resolveRedirect(AuthState auth, String location) {
  // Still reading secure storage: hold on the splash screen rather than flashing login.
  if (!auth.isResolved) {
    return location == Routes.splash ? null : Routes.splash;
  }

  if (!auth.isAuthenticated) {
    return location == Routes.login ? null : Routes.login;
  }

  final home = Routes.homeFor(auth.user!.role);

  // Authenticated users have no business on the splash or login screens.
  if (location == Routes.splash || location == Routes.login) return home;

  // Shared by every role.
  if (location == Routes.profile || location == Routes.notifications) return null;

  // A student typing /teacher/... is sent back to their own area. The backend would
  // refuse the data anyway; this stops the app from rendering an empty teacher shell.
  final ownedPrefix = Routes.prefixFor(auth.user!.role);
  if (!location.startsWith(ownedPrefix)) return home;

  return null;
}
