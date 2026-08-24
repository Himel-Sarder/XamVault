import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/student/widgets/student_exam_tile.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/exam.dart';
import 'package:uniexam/models/student_exam.dart';
import 'package:uniexam/widgets/status_pill.dart';

Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  );
}

StatusColor pillColour(WidgetTester tester) =>
    tester.widget<StatusPill>(find.byType(StatusPill)).colour;

void main() {
  group('the palette exists in both brightnesses', () {
    for (final brightness in Brightness.values) {
      testWidgets('$brightness carries a status palette', (tester) async {
        late StatusPalette palette;
        await tester.pumpWidget(wrap(
          Builder(builder: (context) {
            palette = context.status;
            return const SizedBox();
          }),
          brightness: brightness,
        ));
        final expected =
            brightness == Brightness.light ? StatusPalette.light : StatusPalette.dark;
        expect(palette.warning.container, expected.warning.container);
      });
    }

    testWidgets('body text stays legible against the surface in dark mode',
        (tester) async {
      final theme = AppTheme.dark();
      // The 2021 typography is authored for light backgrounds; if the apply() were
      // dropped, body text would be near-black on a near-black surface.
      expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
      expect(theme.colorScheme.onSurface.computeLuminance(),
          greaterThan(theme.colorScheme.surface.computeLuminance()));
    });
  });

  group('status colour carries meaning', () {
    testWidgets('a pending request is amber, not a third brand hue', (tester) async {
      await tester.pumpWidget(
        wrap(const JoinStatusChip(status: JoinRequestStatus.pending)),
      );
      expect(pillColour(tester), StatusPalette.light.warning);
    });

    testWidgets('approved is settled, rejected is refused', (tester) async {
      await tester.pumpWidget(
        wrap(const JoinStatusChip(status: JoinRequestStatus.approved)),
      );
      expect(pillColour(tester), StatusPalette.light.success);

      await tester.pumpWidget(
        wrap(const JoinStatusChip(status: JoinRequestStatus.rejected)),
      );
      expect(pillColour(tester), StatusPalette.light.danger);
    });

    testWidgets('a draft is quiet and a running exam is not', (tester) async {
      await tester.pumpWidget(wrap(const ExamStatusChip(status: ExamStatus.draft)));
      expect(pillColour(tester), StatusPalette.light.neutral);

      await tester.pumpWidget(wrap(const ExamStatusChip(status: ExamStatus.running)));
      expect(pillColour(tester), StatusPalette.light.success);
    });

    testWidgets('an exam a student can sit right now stands out', (tester) async {
      await tester.pumpWidget(
        wrap(const AvailabilityChip(availability: ExamAvailability.open)),
      );
      expect(pillColour(tester), StatusPalette.light.success);

      await tester.pumpWidget(
        wrap(const AvailabilityChip(availability: ExamAvailability.closed)),
      );
      expect(pillColour(tester), StatusPalette.light.neutral);
    });

    testWidgets('red is spent only on refusal', (tester) async {
      // Reserving it is what keeps it forceful where it matters. Nothing merely
      // inactive or waiting may borrow it.
      const quiet = [
        ExamStatus.draft,
        ExamStatus.completed,
      ];
      for (final status in quiet) {
        await tester.pumpWidget(wrap(ExamStatusChip(status: status)));
        expect(
          pillColour(tester),
          isNot(StatusPalette.light.danger),
          reason: '$status must not read as an error',
        );
      }

      await tester.pumpWidget(wrap(const ExamStatusChip(status: ExamStatus.cancelled)));
      expect(pillColour(tester), StatusPalette.light.danger);
    });
  });

  group('surfaces stay neutral', () {
    testWidgets('the reading surface is not tinted toward the brand hue',
        (tester) async {
      final scheme = AppTheme.light().colorScheme;
      // fromSeed washes surfaces with the seed; a page of exam questions should not sit
      // on a blue tint. Neutral means the channels are close together.
      final surface = scheme.surface;
      final spread = [surface.r, surface.g, surface.b];
      expect(
        spread.reduce((a, b) => a > b ? a : b) -
            spread.reduce((a, b) => a < b ? a : b),
        lessThan(0.03),
        reason: 'surface should read as neutral, not blue',
      );
    });
  });
}
