import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/config/app_config.dart';
import 'package:uniexam/providers/auth_provider.dart';

/// Shown while the persisted session is read and revalidated.
///
/// The router keeps us here until [AuthState.isResolved], so a returning user never sees
/// the login screen flash before being sent to their dashboard.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(authProvider).isResolved) {
        ref.read(authProvider.notifier).restoreSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(AppConfig.appName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
