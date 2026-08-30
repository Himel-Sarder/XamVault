import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uniexam/config/app_config.dart';

/// The palette the brand mark and the splash share.
///
/// Taken from the logo rather than from the Material scheme: the vault body is a very
/// deep navy, and the app's own indigo-to-violet gradient behind it made the artwork
/// look pasted on instead of belonging there.
abstract final class BrandColours {
  static const Color deep = Color(0xFF0A1730);
  static const Color mid = Color(0xFF12294F);
  static const Color edge = Color(0xFF1B3A6B);

  /// The blue the word "Xam" is set in, which is close enough to the app's seed
  /// (#1D4ED8) that the two read as one brand.
  static const Color accent = Color(0xFF3B82F6);
  static const Color accentBright = Color(0xFF60A5FA);

  static const LinearGradient field = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deep, mid, edge],
  );
}

/// The turning ring of a combination lock.
///
/// Three arcs at different radii and speeds, two of them running backwards. A single
/// spinning arc reads as "the framework's spinner, recoloured"; counter-rotation is what
/// makes it read as a mechanism, which is the thing the logo is a picture of.
class VaultDial extends StatefulWidget {
  const VaultDial({
    super.key,
    this.size = 64,
    this.colour,
    this.strokeWidth,
    this.showTicks = true,
  });

  final double size;
  final Color? colour;
  final double? strokeWidth;

  /// The notches around the outer ring. Worth the pixels at 56px and up; below that
  /// they collapse into a smudge, so the small variant turns them off.
  final bool showTicks;

  @override
  State<VaultDial> createState() => _VaultDialState();
}

class _VaultDialState extends State<VaultDial> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = widget.colour ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, _) => CustomPaint(
            painter: _DialPainter(
              t: _turn.value,
              colour: colour,
              strokeWidth: widget.strokeWidth ?? widget.size / 12,
              showTicks: widget.showTicks,
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.t,
    required this.colour,
    required this.strokeWidth,
    required this.showTicks,
  });

  final double t;
  final Color colour;
  final double strokeWidth;
  final bool showTicks;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth / 2;
    final turn = t * 2 * math.pi;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth * 0.7
      ..color = colour.withValues(alpha: 0.16);
    canvas.drawCircle(centre, radius, track);

    // Outer, inner, innermost: each a shorter arc, each slower, and the middle one
    // reversed. The sweeps are deliberately not factors of one another, so the three
    // never line up into a single thick arc.
    _arc(canvas, centre, radius, turn, 2.4, colour, strokeWidth);
    _arc(canvas, centre, radius - strokeWidth * 1.6, -turn * 0.72 + 1.1, 1.5,
        colour.withValues(alpha: 0.75), strokeWidth * 0.8);
    _arc(canvas, centre, radius - strokeWidth * 3.0, turn * 0.45 + 2.3, 0.9,
        colour.withValues(alpha: 0.5), strokeWidth * 0.6);

    if (showTicks) {
      final tick = Paint()
        ..color = colour.withValues(alpha: 0.32)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1, strokeWidth * 0.22);
      // Eight, matching the spokes on the wheel in the logo.
      for (var i = 0; i < 8; i++) {
        final angle = turn * 0.25 + i * math.pi / 4;
        final outer = radius + strokeWidth * 0.1;
        final inner = outer - strokeWidth * 0.55;
        canvas.drawLine(
          centre + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
          centre + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
          tick,
        );
      }
    }
  }

  void _arc(Canvas canvas, Offset centre, double radius, double start, double sweep,
      Color colour, double width) {
    if (radius <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.t != t || old.colour != colour || old.strokeWidth != strokeWidth;
}

/// The logo, at a given size.
///
/// Wrapped rather than used raw so that every screen gets the same asset path, the same
/// filter quality, and the same behaviour if the asset is ever missing: a monogram
/// rather than the framework's broken-image glyph, which would look like a crash.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppConfig.logoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, _, _) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: BrandColours.field,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        child: Text(
          'X',
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w800,
            color: BrandColours.accentBright,
          ),
        ),
      ),
    );
  }
}
