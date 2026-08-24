import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/widgets/status_views.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    if (user == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                _Row(label: 'Name', value: user.name),
                _Row(label: 'User ID', value: user.userId),
                _Row(label: 'Role', value: user.role.label),
                if (user.email != null) _Row(label: 'Email', value: user.email!),
                if (user.department != null)
                  _Row(
                    label: 'Department',
                    value: '${user.department!.name} (${user.department!.code})',
                  ),
                if (user.studentProfile != null) ...[
                  _Row(label: 'Student ID', value: user.studentProfile!.studentId),
                  if (user.studentProfile!.semester != null)
                    _Row(label: 'Semester', value: '${user.studentProfile!.semester}'),
                  if (user.studentProfile!.session != null)
                    _Row(label: 'Session', value: user.studentProfile!.session!),
                ],
                if (user.teacherProfile != null) ...[
                  _Row(label: 'Teacher ID', value: user.teacherProfile!.teacherId),
                  if (user.teacherProfile!.designation != null)
                    _Row(label: 'Designation', value: user.teacherProfile!.designation!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: const Key('profile_sign_out'),
            onPressed: () => _confirmSignOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your user ID and password to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // The router sends us to /login as soon as the state changes.
      await ref.read(authProvider.notifier).logout();
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
