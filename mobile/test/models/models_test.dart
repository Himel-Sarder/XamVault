import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/models/auth_tokens.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/paged.dart';
import 'package:uniexam/models/user.dart';

void main() {
  group('User', () {
    test('parses the compact user object from a login response', () {
      final user = User.fromJson({
        'id': 1,
        'user_id': '20261234',
        'name': 'Demo Student',
        'role': 'student',
      });

      expect(user.id, 1);
      expect(user.role, UserRole.student);
      expect(user.isStudent, isTrue);
      expect(user.studentProfile, isNull);
    });

    test('parses the full /auth/me payload including the profile', () {
      final user = User.fromJson({
        'id': 3,
        'user_id': '20261234',
        'name': 'Demo Student',
        'email': 'student@example.edu',
        'role': 'student',
        'department_id': 1,
        'department': {'id': 1, 'code': 'CSE', 'name': 'Computer Science & Engineering'},
        'is_active': true,
        'student_profile': {
          'student_id': '20261234',
          'department_id': 1,
          'semester': 6,
          'session': '2025-2026',
        },
        'teacher_profile': null,
      });

      expect(user.studentProfile?.semester, 6);
      expect(user.department?.code, 'CSE');
      expect(user.teacherProfile, isNull);
      expect(user.email, 'student@example.edu');
    });

    test('rejects an unknown role instead of defaulting to one', () {
      // Silently mapping an unrecognised role would risk defaulting to a privileged one.
      expect(
        () => User.fromJson({
          'id': 1,
          'user_id': 'x',
          'name': 'x',
          'role': 'superuser',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('AuthTokens parses the token envelope', () {
    final tokens = AuthTokens.fromJson({
      'access_token': 'a',
      'refresh_token': 'r',
      'token_type': 'bearer',
      'expires_in': 1800,
      'user': {'id': 1, 'user_id': 'T1001', 'name': 'Teacher', 'role': 'teacher'},
    });

    expect(tokens.accessToken, 'a');
    expect(tokens.expiresIn, 1800);
    expect(tokens.user.role, UserRole.teacher);
  });

  group('Paged', () {
    test('parses the envelope and reports whether more pages exist', () {
      final page = Paged.fromJson({
        'items': [
          {
            'id': 1,
            'course_code': 'CSE-301',
            'course_name': 'DBMS',
            'created_by': 2,
            'is_active': true,
          }
        ],
        'total': 5,
        'page': 1,
        'page_size': 2,
      }, Course.fromJson);

      expect(page.items.single.courseCode, 'CSE-301');
      expect(page.total, 5);
      expect(page.hasMore, isTrue);
    });

    test('last page reports no more results', () {
      final page = Paged.fromJson(
        {'items': <dynamic>[], 'total': 4, 'page': 2, 'page_size': 2},
        Course.fromJson,
      );
      expect(page.hasMore, isFalse);
    });
  });
}
