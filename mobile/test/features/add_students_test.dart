import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/add_students_screen.dart';
import 'package:uniexam/models/enrolment_candidate.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

EnrolmentCandidate _student(int n, {int year = 4, int semester = 1}) =>
    EnrolmentCandidate(
      id: n,
      userId: '2026${1000 + n}',
      name: 'Student ${n.toString().padLeft(2, '0')}',
      studentId: '2026${1000 + n}',
      studyYear: year,
      semester: semester,
      session: '2025-2026',
    );

Widget wrap(FakeCourseRepository courses) => ProviderScope(
      overrides: [courseRepositoryProvider.overrideWithValue(courses)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AddStudentsScreen(courseId: 1),
      ),
    );

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late FakeCourseRepository courses;

  setUp(() {
    courses = FakeCourseRepository()
      ..candidates = EnrolmentCandidates(
        items: [for (var n = 1; n <= 5; n++) _student(n)],
        truncated: false,
      );
  });

  testWidgets('it lists who could be added, with their stage', (tester) async {
    tall(tester);
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNWidgets(5));
    expect(find.textContaining('4th Year, 1st Semester'), findsWidgets);
  });

  testWidgets('picking a year asks the server to narrow, not the client',
      (tester) async {
    // Filtering on the client would mean fetching every student in the university to
    // show five of them.
    tall(tester);
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('candidate_year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4th Year').last);
    await tester.pumpAndSettle();

    expect(courses.candidateQueries.last.studyYear, 4);
  });

  testWidgets('and the half of it', (tester) async {
    tall(tester);
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('candidate_semester')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2nd Semester').last);
    await tester.pumpAndSettle();

    expect(courses.candidateQueries.last.semester, 2);
  });

  testWidgets('one at a time', (tester) async {
    tall(tester);
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('candidate_20261002')));
    await tester.pumpAndSettle();
    expect(find.text('Add 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_selected_students')));
    await tester.pumpAndSettle();

    expect(courses.bulkBatches, [
      ['20261002']
    ]);
  });

  testWidgets('or the whole cohort at once', (tester) async {
    tall(tester);
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    expect(find.text('Add all 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add_all_students')));
    await tester.pumpAndSettle();

    expect(courses.bulkBatches.single.length, 5);
  });

  testWidgets('a truncated list says so rather than letting "all" mislead',
      (tester) async {
    // "Add all" must never enrol a different set from the one on screen.
    tall(tester);
    courses.candidates = EnrolmentCandidates(
      items: [for (var n = 1; n <= 5; n++) _student(n)],
      truncated: true,
    );
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    expect(find.textContaining('Showing the first 5'), findsOneWidget);
  });

  testWidgets('nobody left to add is explained, not left blank', (tester) async {
    tall(tester);
    courses.candidates = const EnrolmentCandidates(items: [], truncated: false);
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    expect(find.text('Nobody left to add'), findsOneWidget);
    expect(find.byKey(const Key('add_all_students')), findsNothing);
  });

  testWidgets('changing the filter drops a selection made against the old one',
      (tester) async {
    // Otherwise "Add 3" would enrol people who are no longer on screen.
    tall(tester);
    await tester.pumpWidget(wrap(courses));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('candidate_20261002')));
    await tester.pumpAndSettle();
    expect(find.text('Add 1'), findsOneWidget);

    courses.candidates = EnrolmentCandidates(
      items: [_student(9, year: 3, semester: 2)],
      truncated: false,
    );
    await tester.tap(find.byKey(const Key('candidate_year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3rd Year').last);
    await tester.pumpAndSettle();

    expect(find.text('Add selected'), findsOneWidget);
  });
}
