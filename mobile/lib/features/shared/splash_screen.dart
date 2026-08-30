import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/brand_mark.dart';

/// Shown while the persisted session is read and revalidated.
///
/// The router keeps us here until [AuthState.isResolved], so a returning user never sees
/// the login screen flash before being sent to their dashboard.
///
/// The animation is staged rather than simultaneous — the field, then the mark, then the
/// name, then the dial — because everything arriving at once reads as one blunt fade.
/// The whole entrance is over in about a second, which is less than a Render cold start
/// and roughly a warm one, so it covers the wait rather than adding to it.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  Timer? _hintTimer;
  bool _showWakeHint = false;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  // The mark lands first and slightly overshoots, the way a door swings to. Everything
  // after it is a plain fade, so only one thing on screen is ever doing anything
  // interesting at once.
  late final Animation<double> _markScale = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.05, 0.55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _markFade = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.05, 0.40, curve: Curves.easeOut),
  );
  late final Animation<double> _nameFade = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.42, 0.78, curve: Curves.easeOut),
  );
  late final Animation<double> _dialFade = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.62, 1.0, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _enter.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(authProvider).isResolved) {
        ref.read(authProvider.notifier).restoreSession();
      }
    });
    // Start the server waking while the splash is on screen, so a user who then types
    // their password is often past the cold start by the time they press Sign in.
    unawaited(ref.read(authRepositoryProvider).warmUp());
    _hintTimer = Timer(AppConfig.wakeHintAfter, () {
      if (mounted) setState(() => _showWakeHint = true);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // The same navy the Android launch window is painted, so the handover from the
      // native splash to this one is invisible.
      backgroundColor: BrandColours.deep,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: BrandColours.field),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _markFade,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.72, end: 1.0).animate(_markScale),
                        child: const _Mark(),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _nameFade,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.45),
                          end: Offset.zero,
                        ).animate(_nameFade),
                        child: Column(
                          children: [
                            Text(
                              AppConfig.appName,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Examinations, under lock and key',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),
                    FadeTransition(
                      opacity: _dialFade,
                      child: const VaultDial(
                        size: 44,
                        colour: BrandColours.accentBright,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showWakeHint)
                Positioned(
                  left: 32,
                  right: 32,
                  bottom: 40,
                  child: Text(
                    AppConfig.wakeHint,
                    key: const Key('wake_hint'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The logo, sitting in a soft halo.
///
/// The artwork is dark navy on transparent, and dropping it straight onto a dark navy
/// field loses its edges. The halo is what separates the two without putting the logo
/// in a visible box.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 168,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.62, 1.0],
        ),
      ),
      child: const BrandLogo(size: 116),
    );
  }
}
