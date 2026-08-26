<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/models/notification.dart';
import 'package:uniexam/models/question.dart';

/// Where each domain concept gets its colour.
///
/// Kept in one file on purpose. When the mapping lives at the call site, the same idea
/// drifts — a rejected join request ends up red on one screen and grey on another — and
/// nobody notices until a user does.
extension NotificationColour on NotificationCategory {
  StatusColor colour(BuildContext context) {
    final palette = context.status;
    return switch (this) {
      NotificationCategory.examPublished => palette.info,
      // Something is now waiting on the person reading this.
      NotificationCategory.joinRequestReceived => palette.warning,
      NotificationCategory.joinRequestApproved => palette.success,
      NotificationCategory.joinRequestRejected => palette.danger,
      NotificationCategory.examSubmitted => palette.info,
      NotificationCategory.resultPublished => palette.success,
      // A category this build has never heard of gets the neutral tint rather than a
      // guess: better plain than wrong.
      NotificationCategory.unknown => palette.neutral,
    };
  }
}

extension QuestionTypeColour on QuestionType {
  /// Question types are a taxonomy, not a scale, so they take accents rather than
  /// status colours — nothing here is better or worse than anything else.
  StatusColor colour(BuildContext context) {
    final accents = context.accents.accents;
    return switch (this) {
      QuestionType.textMcq => accents[0],
      QuestionType.imageTextOptions => accents[3],
      QuestionType.imageImageOptions => accents[5],
      QuestionType.shortAnswer => accents[1],
      QuestionType.codeAnswer => accents[6],
    };
  }

  IconData get icon => switch (this) {
        QuestionType.textMcq => Icons.radio_button_checked,
        QuestionType.imageTextOptions => Icons.image_outlined,
        QuestionType.imageImageOptions => Icons.collections_outlined,
        QuestionType.shortAnswer => Icons.short_text,
        QuestionType.codeAnswer => Icons.code,
      };

  /// Whether a human has to mark it. Drives the amber "waiting on you" tint in the
  /// grading queue.
  bool get isManuallyMarked =>
      this == QuestionType.shortAnswer || this == QuestionType.codeAnswer;
}

/// A score's colour, by whether it cleared the mark.
///
/// The threshold is passed in rather than assumed: a pass mark is the teacher's to set,
/// and hard-coding 50 here would quietly contradict the figure they chose on the
/// analytics screen.
StatusColor scoreColour(BuildContext context, double percentage, {double pass = 50}) {
  final palette = context.status;
  if (percentage >= pass) return palette.success;
  // Not quite there is not the same as failed outright; the near-miss band keeps red
  // for results that genuinely need attention.
  if (percentage >= pass - 10) return palette.warning;
  return palette.danger;
}

/// A score's colour where no pass mark is known.
///
/// The student's own results list is exactly that case: the passing mark is a policy
/// the university sets and this platform is never told it. So this grades by band and
/// deliberately never reaches for red — painting a 40% red would be the app inventing
/// a verdict it has no standing to give. It still gets darker as the score falls, so
/// the list is scannable without being judgemental.
StatusColor achievementColour(BuildContext context, double percentage) {
  final palette = context.status;
  if (percentage >= 75) return palette.success;
  if (percentage >= 50) return palette.info;
  if (percentage >= 25) return palette.warning;
  return palette.neutral;
}
=======
import 'package:flutter/material.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/models/notification.dart';
import 'package:uniexam/models/question.dart';

/// Where each domain concept gets its colour.
///
/// Kept in one file on purpose. When the mapping lives at the call site, the same idea
/// drifts — a rejected join request ends up red on one screen and grey on another — and
/// nobody notices until a user does.
extension NotificationColour on NotificationCategory {
  StatusColor colour(BuildContext context) {
    final palette = context.status;
    return switch (this) {
      NotificationCategory.examPublished => palette.info,
      // Something is now waiting on the person reading this.
      NotificationCategory.joinRequestReceived => palette.warning,
      NotificationCategory.joinRequestApproved => palette.success,
      NotificationCategory.joinRequestRejected => palette.danger,
      NotificationCategory.examSubmitted => palette.info,
      NotificationCategory.resultPublished => palette.success,
      // A category this build has never heard of gets the neutral tint rather than a
      // guess: better plain than wrong.
      NotificationCategory.unknown => palette.neutral,
    };
  }
}

extension QuestionTypeColour on QuestionType {
  /// Question types are a taxonomy, not a scale, so they take accents rather than
  /// status colours — nothing here is better or worse than anything else.
  StatusColor colour(BuildContext context) {
    final accents = context.accents.accents;
    return switch (this) {
      QuestionType.textMcq => accents[0],
      QuestionType.imageTextOptions => accents[3],
      QuestionType.imageImageOptions => accents[5],
      QuestionType.shortAnswer => accents[1],
      QuestionType.codeAnswer => accents[6],
    };
  }

  IconData get icon => switch (this) {
        QuestionType.textMcq => Icons.radio_button_checked,
        QuestionType.imageTextOptions => Icons.image_outlined,
        QuestionType.imageImageOptions => Icons.collections_outlined,
        QuestionType.shortAnswer => Icons.short_text,
        QuestionType.codeAnswer => Icons.code,
      };

  /// Whether a human has to mark it. Drives the amber "waiting on you" tint in the
  /// grading queue.
  bool get isManuallyMarked =>
      this == QuestionType.shortAnswer || this == QuestionType.codeAnswer;
}

/// A score's colour, by whether it cleared the mark.
///
/// The threshold is passed in rather than assumed: a pass mark is the teacher's to set,
/// and hard-coding 50 here would quietly contradict the figure they chose on the
/// analytics screen.
StatusColor scoreColour(BuildContext context, double percentage, {double pass = 50}) {
  final palette = context.status;
  if (percentage >= pass) return palette.success;
  // Not quite there is not the same as failed outright; the near-miss band keeps red
  // for results that genuinely need attention.
  if (percentage >= pass - 10) return palette.warning;
  return palette.danger;
}

/// A score's colour where no pass mark is known.
///
/// The student's own results list is exactly that case: the passing mark is a policy
/// the university sets and this platform is never told it. So this grades by band and
/// deliberately never reaches for red — painting a 40% red would be the app inventing
/// a verdict it has no standing to give. It still gets darker as the score falls, so
/// the list is scannable without being judgemental.
StatusColor achievementColour(BuildContext context, double percentage) {
  final palette = context.status;
  if (percentage >= 75) return palette.success;
  if (percentage >= 50) return palette.info;
  if (percentage >= 25) return palette.warning;
  return palette.neutral;
}
>>>>>>> c10c483202dfc9e1f56d65a412d901bbf8f3efac
