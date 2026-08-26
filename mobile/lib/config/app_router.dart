<<<<<<< HEAD
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/features/auth/login_screen.dart';
import 'package:uniexam/features/shared/change_password_screen.dart';
import 'package:uniexam/features/shared/courses_screen.dart';
import 'package:uniexam/features/shared/notifications_screen.dart';
import 'package:uniexam/features/shared/profile_screen.dart';
import 'package:uniexam/features/shared/splash_screen.dart';
import 'package:uniexam/features/student/available_exams_screen.dart';
import 'package:uniexam/features/student/exam_attempt_screen.dart';
import 'package:uniexam/features/student/my_results_screen.dart';
import 'package:uniexam/features/student/my_requests_screen.dart';
import 'package:uniexam/features/student/student_dashboard_screen.dart';
import 'package:uniexam/features/student/student_exam_detail_screen.dart';
import 'package:uniexam/features/teacher/admin_dashboard_screen.dart';
import 'package:uniexam/features/teacher/course_detail_screen.dart';
import 'package:uniexam/features/teacher/course_form_screen.dart';
import 'package:uniexam/features/teacher/departments_screen.dart';
import 'package:uniexam/features/teacher/enrollments_screen.dart';
import 'package:uniexam/features/teacher/users_screen.dart';
import 'package:uniexam/features/teacher/exam_detail_screen.dart';
import 'package:uniexam/features/teacher/exam_form_screen.dart';
import 'package:uniexam/features/teacher/analytics_screen.dart';
import 'package:uniexam/features/teacher/attempt_grading_screen.dart';
import 'package:uniexam/features/teacher/exam_results_screen.dart';
import 'package:uniexam/features/teacher/grading_queue_screen.dart';
import 'package:uniexam/features/teacher/join_requests_screen.dart';
import 'package:uniexam/features/teacher/question_bank_screen.dart';
import 'package:uniexam/features/teacher/question_builder_screen.dart';
import 'package:uniexam/features/teacher/teacher_dashboard_screen.dart';
import 'package:uniexam/providers/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter needs a Listenable to know when to re-run `redirect`; this bridges the
  // Riverpod auth state to it without rebuilding the router itself.
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        resolveRedirect(ref.read(authProvider), state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Routes.profile,
        builder: (_, _) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'password',
            builder: (_, _) => const ChangePasswordScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.teacherHome,
        builder: (_, _) => const TeacherDashboardScreen(),
        routes: [
          GoRoute(
            path: 'courses',
            builder: (_, _) => const CoursesScreen(title: 'My Courses'),
            routes: [
              // Declared before ':courseId' so "new" is never parsed as an id.
              GoRoute(path: 'new', builder: (_, _) => const CourseFormScreen()),
              GoRoute(
                path: ':courseId',
                builder: (_, state) => CourseDetailScreen(
                  courseId: int.parse(state.pathParameters['courseId']!),
                ),
                routes: [
                  GoRoute(
                    path: 'exams/new',
                    builder: (_, state) => ExamFormScreen(
                      courseId: int.parse(state.pathParameters['courseId']!),
                    ),
                  ),
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => CourseFormScreen(
                      courseId: int.parse(state.pathParameters['courseId']!),
                    ),
                  ),
                  GoRoute(
                    path: 'enrollments',
                    builder: (_, state) => EnrollmentsScreen(
                      courseId: int.parse(state.pathParameters['courseId']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'question-bank',
            builder: (_, _) => const QuestionBankScreen(),
          ),
          GoRoute(
            path: 'exams/:examId',
            builder: (_, state) => ExamDetailScreen(
              examId: int.parse(state.pathParameters['examId']!),
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) => ExamEditScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'requests',
                builder: (_, state) => JoinRequestsScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'results',
                builder: (_, state) => ExamResultsScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'analytics',
                builder: (_, state) => AnalyticsScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'grading',
                builder: (_, state) => GradingQueueScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
                routes: [
                  GoRoute(
                    path: ':attemptId',
                    builder: (_, state) => AttemptGradingScreen(
                      examId: int.parse(state.pathParameters['examId']!),
                      attemptId: int.parse(state.pathParameters['attemptId']!),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'questions/bank',
                builder: (_, state) => QuestionBankScreen(
                  selectionFor: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'questions/new',
                builder: (_, state) => QuestionCreateScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'questions/:questionId',
                builder: (_, state) => QuestionEditScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                  examQuestionId: int.parse(state.pathParameters['questionId']!),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.studentHome,
        builder: (_, _) => const StudentDashboardScreen(),
        routes: [
          GoRoute(
            path: 'courses',
            builder: (_, _) => const CoursesScreen(title: 'Enrolled Courses'),
          ),
          GoRoute(
            path: 'exams',
            builder: (_, _) => const AvailableExamsScreen(),
            routes: [
              GoRoute(
                path: ':examId',
                builder: (_, state) => StudentExamDetailScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
            ],
          ),
          GoRoute(path: 'requests', builder: (_, _) => const MyRequestsScreen()),
          GoRoute(path: 'results', builder: (_, _) => const MyResultsScreen()),
          GoRoute(
            path: 'attempt/:attemptId',
            builder: (_, state) => ExamAttemptScreen(
              attemptId: int.parse(state.pathParameters['attemptId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.adminHome,
        builder: (_, _) => const AdminDashboardScreen(),
        routes: [
          GoRoute(path: 'departments', builder: (_, _) => const DepartmentsScreen()),
          GoRoute(path: 'users', builder: (_, _) => const UsersScreen()),
          GoRoute(
            path: 'courses',
            builder: (_, _) => const CoursesScreen(title: 'All Courses'),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const CourseFormScreen()),
              GoRoute(
                path: ':courseId/edit',
                builder: (_, state) => CourseFormScreen(
                  courseId: int.parse(state.pathParameters['courseId']!),
                ),
              ),
              GoRoute(
                path: ':courseId/enrollments',
                builder: (_, state) => EnrollmentsScreen(
                  courseId: int.parse(state.pathParameters['courseId']!),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
=======
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/features/auth/login_screen.dart';
import 'package:uniexam/features/shared/change_password_screen.dart';
import 'package:uniexam/features/shared/courses_screen.dart';
import 'package:uniexam/features/shared/notifications_screen.dart';
import 'package:uniexam/features/shared/profile_screen.dart';
import 'package:uniexam/features/shared/splash_screen.dart';
import 'package:uniexam/features/student/available_exams_screen.dart';
import 'package:uniexam/features/student/exam_attempt_screen.dart';
import 'package:uniexam/features/student/my_results_screen.dart';
import 'package:uniexam/features/student/my_requests_screen.dart';
import 'package:uniexam/features/student/student_dashboard_screen.dart';
import 'package:uniexam/features/student/student_exam_detail_screen.dart';
import 'package:uniexam/features/teacher/admin_dashboard_screen.dart';
import 'package:uniexam/features/teacher/course_detail_screen.dart';
import 'package:uniexam/features/teacher/course_form_screen.dart';
import 'package:uniexam/features/teacher/departments_screen.dart';
import 'package:uniexam/features/teacher/enrollments_screen.dart';
import 'package:uniexam/features/teacher/users_screen.dart';
import 'package:uniexam/features/teacher/exam_detail_screen.dart';
import 'package:uniexam/features/teacher/exam_form_screen.dart';
import 'package:uniexam/features/teacher/analytics_screen.dart';
import 'package:uniexam/features/teacher/attempt_grading_screen.dart';
import 'package:uniexam/features/teacher/exam_results_screen.dart';
import 'package:uniexam/features/teacher/grading_queue_screen.dart';
import 'package:uniexam/features/teacher/join_requests_screen.dart';
import 'package:uniexam/features/teacher/question_bank_screen.dart';
import 'package:uniexam/features/teacher/question_builder_screen.dart';
import 'package:uniexam/features/teacher/teacher_dashboard_screen.dart';
import 'package:uniexam/providers/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter needs a Listenable to know when to re-run `redirect`; this bridges the
  // Riverpod auth state to it without rebuilding the router itself.
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        resolveRedirect(ref.read(authProvider), state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Routes.profile,
        builder: (_, _) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'password',
            builder: (_, _) => const ChangePasswordScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.teacherHome,
        builder: (_, _) => const TeacherDashboardScreen(),
        routes: [
          GoRoute(
            path: 'courses',
            builder: (_, _) => const CoursesScreen(title: 'My Courses'),
            routes: [
              // Declared before ':courseId' so "new" is never parsed as an id.
              GoRoute(path: 'new', builder: (_, _) => const CourseFormScreen()),
              GoRoute(
                path: ':courseId',
                builder: (_, state) => CourseDetailScreen(
                  courseId: int.parse(state.pathParameters['courseId']!),
                ),
                routes: [
                  GoRoute(
                    path: 'exams/new',
                    builder: (_, state) => ExamFormScreen(
                      courseId: int.parse(state.pathParameters['courseId']!),
                    ),
                  ),
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => CourseFormScreen(
                      courseId: int.parse(state.pathParameters['courseId']!),
                    ),
                  ),
                  GoRoute(
                    path: 'enrollments',
                    builder: (_, state) => EnrollmentsScreen(
                      courseId: int.parse(state.pathParameters['courseId']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'question-bank',
            builder: (_, _) => const QuestionBankScreen(),
          ),
          GoRoute(
            path: 'exams/:examId',
            builder: (_, state) => ExamDetailScreen(
              examId: int.parse(state.pathParameters['examId']!),
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) => ExamEditScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'requests',
                builder: (_, state) => JoinRequestsScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'results',
                builder: (_, state) => ExamResultsScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'analytics',
                builder: (_, state) => AnalyticsScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'grading',
                builder: (_, state) => GradingQueueScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
                routes: [
                  GoRoute(
                    path: ':attemptId',
                    builder: (_, state) => AttemptGradingScreen(
                      examId: int.parse(state.pathParameters['examId']!),
                      attemptId: int.parse(state.pathParameters['attemptId']!),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'questions/bank',
                builder: (_, state) => QuestionBankScreen(
                  selectionFor: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'questions/new',
                builder: (_, state) => QuestionCreateScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
              GoRoute(
                path: 'questions/:questionId',
                builder: (_, state) => QuestionEditScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                  examQuestionId: int.parse(state.pathParameters['questionId']!),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.studentHome,
        builder: (_, _) => const StudentDashboardScreen(),
        routes: [
          GoRoute(
            path: 'courses',
            builder: (_, _) => const CoursesScreen(title: 'Enrolled Courses'),
          ),
          GoRoute(
            path: 'exams',
            builder: (_, _) => const AvailableExamsScreen(),
            routes: [
              GoRoute(
                path: ':examId',
                builder: (_, state) => StudentExamDetailScreen(
                  examId: int.parse(state.pathParameters['examId']!),
                ),
              ),
            ],
          ),
          GoRoute(path: 'requests', builder: (_, _) => const MyRequestsScreen()),
          GoRoute(path: 'results', builder: (_, _) => const MyResultsScreen()),
          GoRoute(
            path: 'attempt/:attemptId',
            builder: (_, state) => ExamAttemptScreen(
              attemptId: int.parse(state.pathParameters['attemptId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.adminHome,
        builder: (_, _) => const AdminDashboardScreen(),
        routes: [
          GoRoute(path: 'departments', builder: (_, _) => const DepartmentsScreen()),
          GoRoute(path: 'users', builder: (_, _) => const UsersScreen()),
          GoRoute(
            path: 'courses',
            builder: (_, _) => const CoursesScreen(title: 'All Courses'),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const CourseFormScreen()),
              GoRoute(
                path: ':courseId/edit',
                builder: (_, state) => CourseFormScreen(
                  courseId: int.parse(state.pathParameters['courseId']!),
                ),
              ),
              GoRoute(
                path: ':courseId/enrollments',
                builder: (_, state) => EnrollmentsScreen(
                  courseId: int.parse(state.pathParameters['courseId']!),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
