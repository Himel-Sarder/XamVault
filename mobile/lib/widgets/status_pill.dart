import 'package:flutter/material.dart';
import 'package:uniexam/config/theme.dart';

/// One status, rendered the same way everywhere.
///
/// There were three near-identical pill implementations before this — teacher exam
/// status, student availability, join request — which is how they drifted apart by a
/// pixel or two. The shape belongs in one place; only the meaning differs.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.colour});

  final String label;
  final StatusColor colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colour.container,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colour.foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}
