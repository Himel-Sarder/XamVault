import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/models/study_stage.dart';

void main() {
  group('how a stage is written', () {
    test('years and semesters read as the university says them', () {
      expect(ordinalYear(1), '1st Year');
      expect(ordinalYear(2), '2nd Year');
      expect(ordinalYear(3), '3rd Year');
      expect(ordinalYear(4), '4th Year');
      expect(ordinalSemester(1), '1st Semester');
      expect(ordinalSemester(2), '2nd Semester');
    });

    test('both together', () {
      expect(studyStage(year: 3, semester: 2), '3rd Year, 2nd Semester');
    });

    test('whichever half is known', () {
      // A record with only one of the two is still worth showing.
      expect(studyStage(year: 2), '2nd Year');
      expect(studyStage(semester: 1), '1st Semester');
    });

    test('neither returns nothing at all', () {
      // So a caller drops the line rather than printing a label with nothing after it.
      expect(studyStage(), isNull);
    });
  });
}
