import 'package:flutter/material.dart';
import 'package:uniexam/config/theme.dart';

/// A titled section, with a coloured mark so a long scrolling screen has landmarks.
///
/// Before this, every screen's sections were separated by nothing but a slightly bolder
/// line of text, which on a page of six cards gives a reader nothing to navigate by.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.colour,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final IconData icon;

  /// Defaults to the informational tint; pass one when the section itself has a
  /// meaning, such as a queue of work that is waiting.
  final StatusColor? colour;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = colour ?? context.status.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.container,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: tint.foreground),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One number worth reading at a glance.
///
/// A figure that matters — a cohort average, a count of papers waiting — should not be
/// the same size and weight as the label next to it. The tint is what lets a row of
/// four be scanned rather than read.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.colour,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusColor colour;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.container,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colour.foreground),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colour.foreground,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colour.foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colour.foreground),
            ),
          ],
        ],
      ),
    );
  }
}

/// A proportional bar, for distributions and pass rates.
///
/// Rounded, on a track, and never zero-width when the value is non-zero: a band with
/// one student in it must still be visible, or the chart quietly lies about it.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.fraction,
    required this.colour,
    this.height = 10,
  });

  /// 0..1. Values outside that range are clamped rather than overflowing the track.
  final double fraction;
  final StatusColor colour;
  final double height;

  @override
  Widget build(BuildContext context) {
    final value = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(
            height: height,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          FractionallySizedBox(
            widthFactor: value == 0 ? 0 : value.clamp(0.02, 1.0),
            child: Container(height: height, color: colour.foreground),
          ),
        ],
      ),
    );
  }
}
