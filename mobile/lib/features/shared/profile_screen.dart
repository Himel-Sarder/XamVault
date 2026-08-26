import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uniexam/config/routes.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/widgets/section.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Who you are, what you belong to, and the two things you can do about it.
///
/// The detail was a column of label/value rows with a fixed 110px label column, which
/// truncated the longer ones and gave a reader nothing to navigate by. It is grouped
/// now — identity, then academic record, then account — because those are three
/// different questions and a scroll should show which one it is answering.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    if (user == null) return const Scaffold(body: LoadingView());

    final student = user.studentProfile;
    final teacher = user.teacherProfile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Hero(user: user),
          const SizedBox(height: 24),

          if (user.department != null || student != null || teacher != null) ...[
            const SectionHeader(
              title: 'Academic record',
              icon: Icons.school_outlined,
            ),
            Card(
              child: Column(
                children: [
                  if (user.department != null)
                    _Detail(
                      icon: Icons.apartment_rounded,
                      label: 'Department',
                      value: user.department!.name,
                      trailing: user.department!.code,
                      // The department's own colour, the same one its courses carry,
                      // so the association is visible rather than merely stated.
                      colour: context.accents.forKey(user.department!.code),
                    ),
                  if (student != null) ...[
                    _Detail(
                      icon: Icons.badge_outlined,
                      label: 'Student ID',
                      value: student.studentId,
                      colour: context.accents.accents[0],
                    ),
                    if (student.semester != null)
                      _Detail(
                        icon: Icons.calendar_view_month_outlined,
                        label: 'Semester',
                        value: 'Semester ${student.semester}',
                        colour: context.accents.accents[3],
                      ),
                    if (student.session != null)
                      _Detail(
                        icon: Icons.date_range_outlined,
                        label: 'Session',
                        value: student.session!,
                        colour: context.accents.accents[1],
                      ),
                  ],
                  if (teacher != null) ...[
                    _Detail(
                      icon: Icons.badge_outlined,
                      label: 'Teacher ID',
                      value: teacher.teacherId,
                      colour: context.accents.accents[0],
                    ),
                    if (teacher.designation != null)
                      _Detail(
                        icon: Icons.workspace_premium_outlined,
                        label: 'Designation',
                        value: teacher.designation!,
                        colour: context.accents.accents[4],
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          const SectionHeader(
            title: 'Account',
            icon: Icons.manage_accounts_outlined,
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (user.email != null)
                  _Detail(
                    icon: Icons.mail_outline,
                    label: 'Email',
                    value: user.email!,
                    colour: context.status.info,
                  ),
                _ActionTile(
                  tileKey: const Key('profile_change_password'),
                  icon: Icons.lock_reset_rounded,
                  title: 'Change password',
                  subtitle: 'Signs you out on every other device',
                  colour: context.status.warning,
                  onTap: () => context.push(Routes.changePassword),
                ),
                _ActionTile(
                  tileKey: const Key('profile_sign_out'),
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  subtitle: 'You will need your ID and password again',
                  colour: context.status.danger,
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ],
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
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.status.danger.foreground,
              foregroundColor: Colors.white,
            ),
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

/// Name, role and ID on the brand gradient.
///
/// The one surface here that carries identity rather than content, which is what makes
/// a gradient worth its weight — the same reasoning as the dashboard header, and the
/// same gradient, so arriving here feels like the same app rather than another screen.
class _Hero extends StatelessWidget {
  const _Hero({required this.user});

  final User user;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 2),
            ),
            child: Text(
              _initials(user.name),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _HeroChip(
                icon: switch (user.role) {
                  UserRole.admin => Icons.shield_outlined,
                  UserRole.teacher => Icons.school_outlined,
                  UserRole.student => Icons.person_outline,
                },
                label: user.role.label,
              ),
              _HeroChip(icon: Icons.tag, label: user.userId),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// One fact, with its own tinted mark.
///
/// Stacked rather than put in a fixed label column: "Computer Science & Engineering"
/// does not fit beside a 110px label, and truncating a department name to make a grid
/// line up is the wrong trade.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.icon,
    required this.label,
    required this.value,
    required this.colour,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final StatusColor colour;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colour.container,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: colour.foreground),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: colour.container,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trailing!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colour.foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colour,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final StatusColor colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      key: tileKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colour.container,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: colour.foreground),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colour.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
