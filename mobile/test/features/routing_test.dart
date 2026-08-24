import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';

AuthState _authenticated(UserRole role) => AuthState(
      status: AuthStatus.authenticated,
      user: User(id: 1, userId: 'u1', name: 'Test User', role: role),
    );

const _unauthenticated = AuthState(status: AuthStatus.unauthenticated);
const _unknown = AuthState();

void main() {
  group('while the session is still being restored', () {
    test('every location is held on the splash screen', () {
      expect(resolveRedirect(_unknown, Routes.login), Routes.splash);
      expect(resolveRedirect(_unknown, Routes.teacherHome), Routes.splash);
    });

    test('the splash screen itself is left alone', () {
      expect(resolveRedirect(_unknown, Routes.splash), isNull);
    });
  });

  group('unauthenticated', () {
    test('is sent to login from anywhere', () {
      expect(resolveRedirect(_unauthenticated, Routes.teacherHome), Routes.login);
      expect(resolveRedirect(_unauthenticated, Routes.studentCourses), Routes.login);
      expect(resolveRedirect(_unauthenticated, Routes.profile), Routes.login);
      expect(resolveRedirect(_unauthenticated, Routes.splash), Routes.login);
    });

    test('stays on the login screen', () {
      expect(resolveRedirect(_unauthenticated, Routes.login), isNull);
    });
  });

  group('authenticated', () {
    test('each role lands on its own home', () {
      expect(resolveRedirect(_authenticated(UserRole.teacher), Routes.login),
          Routes.teacherHome);
      expect(resolveRedirect(_authenticated(UserRole.student), Routes.login),
          Routes.studentHome);
      expect(
          resolveRedirect(_authenticated(UserRole.admin), Routes.login), Routes.adminHome);
    });

    test('the splash and login screens are not reachable again', () {
      expect(resolveRedirect(_authenticated(UserRole.teacher), Routes.splash),
          Routes.teacherHome);
    });

    test('a student cannot open teacher routes', () {
      expect(resolveRedirect(_authenticated(UserRole.student), Routes.teacherHome),
          Routes.studentHome);
      expect(resolveRedirect(_authenticated(UserRole.student), Routes.teacherCourses),
          Routes.studentHome);
      expect(resolveRedirect(_authenticated(UserRole.student), Routes.adminHome),
          Routes.studentHome);
    });

    test('a teacher cannot open student routes', () {
      expect(resolveRedirect(_authenticated(UserRole.teacher), Routes.studentHome),
          Routes.teacherHome);
    });

    test('each role may stay inside its own area', () {
      expect(resolveRedirect(_authenticated(UserRole.teacher), Routes.teacherCourses), isNull);
      expect(resolveRedirect(_authenticated(UserRole.student), Routes.studentCourses), isNull);
    });

    test('the profile screen is shared by every role', () {
      for (final role in UserRole.values) {
        expect(resolveRedirect(_authenticated(role), Routes.profile), isNull);
      }
    });
  });
}
