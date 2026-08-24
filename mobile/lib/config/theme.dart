import 'package:flutter/material.dart';

/// One status colour and the surface it sits on.
class StatusColor {
  const StatusColor({required this.foreground, required this.container});

  final Color foreground;
  final Color container;

  static StatusColor lerp(StatusColor a, StatusColor b, double t) => StatusColor(
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
        container: Color.lerp(a.container, b.container, t)!,
      );
}

/// Colours that carry a *meaning* rather than a brand.
///
/// Material's scheme has three brand hues and one error. An exam platform has more
/// states than that — draft, published, running, pending, approved, rejected, closed —
/// and mapping them onto `primary` / `secondary` / `tertiary` makes the choice
/// arbitrary: "awaiting approval" ends up whatever hue the seed algorithm happened to
/// generate, which is why it reads as decoration rather than information.
///
/// Here each state gets the colour a reader already expects. Amber means waiting, green
/// means settled, red is spent only on genuine refusal, and grey means "not yet live".
/// Because red is reserved, it keeps its force where it matters.
@immutable
class StatusPalette extends ThemeExtension<StatusPalette> {
  const StatusPalette({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
  });

  /// Settled and good: approved, open, passed.
  final StatusColor success;

  /// Waiting on someone: pending review, unmarked, in progress.
  final StatusColor warning;

  /// Refused or stopped: rejected, cancelled, failed.
  final StatusColor danger;

  /// Live and informational: published, upcoming.
  final StatusColor info;

  /// Not yet live, or no longer: draft, closed, none.
  final StatusColor neutral;

  static const light = StatusPalette(
    success: StatusColor(foreground: Color(0xFF10603C), container: Color(0xFFD7F0E2)),
    warning: StatusColor(foreground: Color(0xFF7A4E00), container: Color(0xFFFBEACA)),
    danger: StatusColor(foreground: Color(0xFF9B221C), container: Color(0xFFF9DEDC)),
    info: StatusColor(foreground: Color(0xFF0E4374), container: Color(0xFFD9E6F4)),
    neutral: StatusColor(foreground: Color(0xFF4A5568), container: Color(0xFFEAEEF3)),
  );

  static const dark = StatusPalette(
    success: StatusColor(foreground: Color(0xFF7FD8A6), container: Color(0xFF11412B)),
    warning: StatusColor(foreground: Color(0xFFEFC377), container: Color(0xFF44300A)),
    danger: StatusColor(foreground: Color(0xFFF2B8B5), container: Color(0xFF5A1512)),
    info: StatusColor(foreground: Color(0xFFA6C8EA), container: Color(0xFF11324F)),
    neutral: StatusColor(foreground: Color(0xFFC3C9D3), container: Color(0xFF2A303A)),
  );

  @override
  StatusPalette copyWith({
    StatusColor? success,
    StatusColor? warning,
    StatusColor? danger,
    StatusColor? info,
    StatusColor? neutral,
  }) {
    return StatusPalette(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  StatusPalette lerp(covariant StatusPalette? other, double t) {
    if (other == null) return this;
    return StatusPalette(
      success: StatusColor.lerp(success, other.success, t),
      warning: StatusColor.lerp(warning, other.warning, t),
      danger: StatusColor.lerp(danger, other.danger, t),
      info: StatusColor.lerp(info, other.info, t),
      neutral: StatusColor.lerp(neutral, other.neutral, t),
    );
  }
}

/// Convenience so a widget can write `context.status.warning` instead of reaching
/// through `Theme.of(context).extension<StatusPalette>()!` at every call site.
extension StatusPaletteAccess on BuildContext {
  StatusPalette get status =>
      Theme.of(this).extension<StatusPalette>() ?? StatusPalette.light;
}

/// Material 3 theme, defined once for both light and dark.
class AppTheme {
  const AppTheme._();

  /// A deep institutional blue. Universities are not consumer products: the palette
  /// should read as considered and calm, and stay out of the way of a paper someone is
  /// being examined on.
  static const Color _seed = Color(0xFF0F4C81);

  // A single scale, so nothing is rounded by eye at a call site.
  static const double _radiusField = 12;
  static const double _radiusCard = 16;
  static const double _radiusDialog = 20;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = _scheme(brightness);
    final text = _textTheme(scheme);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      extensions: [isLight ? StatusPalette.light : StatusPalette.dark],

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        // Flat until content slides beneath it, then a hairline of separation. A bar
        // that is always raised competes with the content for attention.
        scrolledUnderElevation: 3,
        titleTextStyle: text.titleLarge,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          // Bordered rather than shadowed: on a list of twenty cards, twenty shadows
          // read as noise, while a hairline still separates them cleanly.
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? scheme.surfaceContainerLow : scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusField),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusField),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusField),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusField),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusField),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        helperStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Height only. `Size.fromHeight` would set the *width* minimum to infinity,
          // which a Row cannot satisfy: it offers its children unbounded width, and a
          // minimum of infinity against that fails layout outright, leaving the button
          // with no size to hit-test. Stretching is the parent's business, so the
          // buttons that should fill their row say so themselves with a SizedBox.
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusField),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusField),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(56, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusField),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusCard)),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusField)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusDialog),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusField),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: const StadiumBorder(),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 3,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusField),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
    );
  }

  /// The generated scheme, with the surface family flattened.
  ///
  /// `fromSeed` tints every surface toward the brand hue. That suits a consumer app;
  /// on a page of exam questions it puts a faint blue wash behind text that has to be
  /// read carefully for an hour. The neutrals here stay neutral, and the blue is spent
  /// only where it means something.
  static ColorScheme _scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    if (brightness == Brightness.light) {
      return base.copyWith(
        surface: const Color(0xFFFAFBFC),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF6F8FA),
        surfaceContainer: const Color(0xFFF1F4F7),
        surfaceContainerHigh: const Color(0xFFEAEEF3),
        surfaceContainerHighest: const Color(0xFFE3E8EE),
        onSurface: const Color(0xFF1A1F26),
        onSurfaceVariant: const Color(0xFF5A6472),
        outline: const Color(0xFF9AA4B2),
        outlineVariant: const Color(0xFFDCE2E9),
      );
    }
    return base.copyWith(
      surface: const Color(0xFF101418),
      surfaceContainerLowest: const Color(0xFF0B0E12),
      surfaceContainerLow: const Color(0xFF161B21),
      surfaceContainer: const Color(0xFF1A2027),
      surfaceContainerHigh: const Color(0xFF232A33),
      surfaceContainerHighest: const Color(0xFF2C343E),
      onSurface: const Color(0xFFE6EAEF),
      onSurfaceVariant: const Color(0xFFA9B2BE),
      outline: const Color(0xFF6B7684),
      outlineVariant: const Color(0xFF2E3641),
    );
  }

  /// Headings are tightened and weighted; body text is left alone.
  ///
  /// Negative tracking on large text is what stops a heading looking like body text
  /// that happens to be big. Body sizes keep default spacing, because tightening text
  /// meant to be read at length costs legibility for no gain.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = Typography.material2021(colorScheme: scheme).black.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      bodySmall: base.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}
