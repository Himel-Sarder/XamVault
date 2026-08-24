import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/admin_provider.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// The user directory. Administrator only.
///
/// Accounts are deactivated, never deleted: exams, attempts and results all point at
/// their author, and a deleted user would take that record with them. A deactivated
/// account cannot sign in, which is what the request actually calls for.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _search = TextEditingController();
  UserRole? _role;
  String? _query;
  int? _busyId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final departments = ref.read(departmentsProvider).valueOrNull ?? const <Department>[];
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _NewUserDialog(departments: departments),
    );
    if (created ?? false) {
      ref.invalidate(adminUsersProvider);
    }
  }

  Future<void> _setActive(User user, bool active) async {
    setState(() => _busyId = user.id);
    try {
      await ref.read(adminRepositoryProvider).updateUser(user.id, isActive: active);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
        ref.invalidate(adminUsersProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider((role: _role, search: _query)));

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_user'),
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New user'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const Key('user_search'),
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name or ID',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query == null
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = null);
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                setState(() => _query = trimmed.isEmpty ? null : trimmed);
              },
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  key: const Key('role_any'),
                  label: const Text('Everyone'),
                  selected: _role == null,
                  onSelected: (_) => setState(() => _role = null),
                ),
                for (final role in UserRole.values) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    key: Key('role_${role.name}'),
                    label: Text(role.label),
                    selected: _role == role,
                    onSelected: (_) => setState(() => _role = role),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: users.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorView(
                message:
                    error is ApiException ? error.message : 'Could not load the users.',
                onRetry: () => ref.invalidate(adminUsersProvider),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return const EmptyView(
                    title: 'No users match',
                    subtitle: 'Try a different search, or clear the role filter.',
                    icon: Icons.person_search_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _tile(page.items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(User user) {
    final theme = Theme.of(context);
    final busy = _busyId == user.id;

    return Card(
      child: ListTile(
        key: Key('user_${user.id}'),
        leading: CircleAvatar(
          backgroundColor: user.isActive
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            switch (user.role) {
              UserRole.admin => Icons.shield_outlined,
              UserRole.teacher => Icons.school_outlined,
              UserRole.student => Icons.person_outline,
            },
            color: user.isActive
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(user.name),
        subtitle: Text(
          user.isActive
              ? '${user.userId} · ${user.role.label}'
              : '${user.userId} · ${user.role.label} · deactivated',
        ),
        trailing: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Switch(
                key: Key('user_active_${user.id}'),
                value: user.isActive,
                onChanged: (value) => _setActive(user, value),
              ),
      ),
    );
  }
}

/// Creating an account. The role decides which profile fields the API requires, so the
/// form asks for exactly those and no more.
class _NewUserDialog extends ConsumerStatefulWidget {
  const _NewUserDialog({required this.departments});

  final List<Department> departments;

  @override
  ConsumerState<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends ConsumerState<_NewUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userId = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _roleId = TextEditingController();

  UserRole _role = UserRole.student;
  int? _departmentId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    _name.dispose();
    _email.dispose();
    _roleId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final email = _email.text.trim();
    final profileId = _roleId.text.trim();
    try {
      await ref.read(adminRepositoryProvider).createUser(
            userId: _userId.text.trim(),
            password: _password.text,
            name: _name.text.trim(),
            role: _role,
            email: email.isEmpty ? null : email,
            departmentId: _departmentId,
            studentId: _role == UserRole.student ? profileId : null,
            teacherId: _role == UserRole.teacher ? profileId : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsProfileId = _role != UserRole.admin;

    return AlertDialog(
      title: const Text('New user'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<UserRole>(
                  key: const Key('new_user_role'),
                  segments: [
                    for (final role in UserRole.values)
                      ButtonSegment(value: role, label: Text(role.label)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (selection) =>
                      setState(() => _role = selection.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('new_user_id'),
                  controller: _userId,
                  decoration: const InputDecoration(
                    labelText: 'Login ID',
                    helperText: 'What they type to sign in',
                  ),
                  validator: (value) => (value == null || value.trim().length < 3)
                      ? 'At least 3 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('new_user_name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter a name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('new_user_password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Initial password',
                    helperText: 'At least 8 characters. They can change it after signing in.',
                  ),
                  validator: (value) =>
                      (value == null || value.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('new_user_email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                ),
                if (needsProfileId) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('new_user_profile_id'),
                    controller: _roleId,
                    decoration: InputDecoration(
                      labelText:
                          _role == UserRole.student ? 'Student ID' : 'Teacher ID',
                      helperText: 'Required for this role',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Required for this role'
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  key: const Key('new_user_department'),
                  initialValue: _departmentId,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('None')),
                    for (final department in widget.departments)
                      DropdownMenuItem<int?>(
                        value: department.id,
                        child: Text('${department.code} — ${department.name}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _departmentId = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('new_user_error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('new_user_submit'),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
