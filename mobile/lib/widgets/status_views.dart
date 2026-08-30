import 'package:flutter/material.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/widgets/brand_mark.dart';

/// The app's waiting state, wherever a screen is fetching something.
///
/// A turning combination dial rather than the framework's spinner: it is the mechanism
/// the logo is a picture of, so a wait looks like part of this app rather than part of
/// Flutter. One widget for all twenty-seven call sites, so no two screens invent their
/// own idea of what loading looks like.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VaultDial(size: 58),
          if (message != null) ...[
            const SizedBox(height: 20),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// The same dial, sized to sit inside a button or a list row.
///
/// Small enough that the outer notches would turn to mush, so they are off.
///
/// The colour comes from the surrounding [IconTheme] rather than the scheme's primary,
/// which is what a button sets for its own contents. A plain progress indicator inside a
/// filled button draws itself primary-on-primary -- blue on blue, all but invisible --
/// and every call site has to remember to override it. This one is right by default.
class InlineLoader extends StatelessWidget {
  const InlineLoader({super.key, this.size = 18, this.colour});

  final double size;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return VaultDial(
      size: size,
      colour: colour ?? IconTheme.of(context).color,
      strokeWidth: size / 7,
      showTicks: false,
    );
  }
}

/// The icon block shared by the empty and error states.
///
/// A bare 48px glyph on a white field is the cheapest-looking thing in any app; sitting
/// it in a tinted, rounded square costs nothing and makes an empty screen look designed
/// rather than unfinished.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.colour});

  final IconData icon;
  final StatusColor colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour.container,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(icon, size: 34, color: colour.foreground),
    );
  }
}

/// Failure state with a retry affordance.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Glyph(icon: Icons.cloud_off_rounded, colour: context.status.danger),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown where a list has nothing in it yet.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.action,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// An empty list is usually a place where something *should* be created, so the
  /// screen may offer the way to do it instead of only reporting the absence.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Info, not error: nothing has gone wrong here.
            _Glyph(icon: icon ?? Icons.inbox_rounded, colour: context.status.info),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
