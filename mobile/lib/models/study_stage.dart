/// How a year and a semester are written, in one place.
///
/// The university says "3rd Year, 2nd Semester". Spelling that out at each call site
/// is how a screen ends up saying "Year 3" while the one beside it says "3rd Year",
/// which reads as two different things about the same student.
library;

/// 1 to 4, as the university says it.
String ordinalYear(int year) => '${_ordinal(year)} Year';

/// 1 or 2 — the two halves of a year.
String ordinalSemester(int semester) => '${_ordinal(semester)} Semester';

/// Both together, or whichever is known.
///
/// Returns null when neither is set, so a caller can drop the line entirely rather
/// than printing a label with nothing after it.
String? studyStage({int? year, int? semester}) {
  if (year == null && semester == null) return null;
  if (year == null) return ordinalSemester(semester!);
  if (semester == null) return ordinalYear(year);
  return '${ordinalYear(year)}, ${ordinalSemester(semester)}';
}

String _ordinal(int value) => switch (value) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      // 4th covers the rest of the range either field allows; anything outside it is
      // shown plainly rather than guessed at.
      _ => '${value}th',
    };
