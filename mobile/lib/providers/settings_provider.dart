import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/models/app_settings.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

/// The installation's own settings.
///
/// Not autoDispose: the university name is read by the dashboard header and by the
/// settings screen, changes about once in the life of an installation, and refetching
/// it on every screen entry would be waste.
final appSettingsProvider = FutureProvider<AppSettings>((ref) async {
  // Signed out, there is nobody to read it for — and the endpoint would refuse.
  ref.watch(authProvider.select((state) => state.user?.id));
  return ref.watch(settingsRepositoryProvider).get();
});
