import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/study_stage.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/admin_provider.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/config/theme.dart';
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
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _NewUserDialog(),
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

  Future<void> _confirmDelete(User user) async {
    final admin = ref.read(adminRepositoryProvider);

    Map<String, int> impact;
    try {
      impact = await admin.deletionImpact(user.id);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    if (!mounted) return;

    final owns = ['courses', 'exams', 'questions']
        .where((key) => (impact[key] ?? 0) > 0)
        .map((key) => '${impact[key]} $key')
        .toList();
    final loses = ['attempts', 'results', 'enrolments']
        .where((key) => (impact[key] ?? 0) > 0)
        .map((key) => '${impact[key]} $key')
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('delete_user_dialog'),
        title: Text(owns.isEmpty ? 'Delete this account?' : 'This account cannot be deleted'),
        content: Text(
          owns.isNotEmpty
              // Blocked at the database, because an exam other students sat must not
              // lose its author. Said here so it is read before the attempt, not after.
              ? '${user.name} authored ${owns.join(', ')}. Exams and results belonging '
                  'to other people depend on those, so the account cannot be removed. '
                  'Reassign or delete that work first.'
              : loses.isEmpty
                  ? '${user.name} (${user.userId}) will be removed. They have no exam '
                      'history, so nothing else goes with them.'
                  : '${user.name} (${user.userId}) will be removed, and so will their '
                      '${loses.join(', ')}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(owns.isEmpty ? 'Keep' : 'Close'),
          ),
          if (owns.isEmpty)
            FilledButton(
              key: const Key('confirm_delete_user'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: loses.isEmpty
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: dialogContext.status.danger.foreground,
                      foregroundColor: Colors.white,
                    ),
              child: Text(loses.isEmpty ? 'Delete' : 'Delete everything'),
            ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _busyId = user.id);
    try {
      await admin.deleteUser(user.id);
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
    final busy = _busyId == user.id;
    final roleColour = user.isActive
        ? switch (user.role) {
            UserRole.admin => context.accents.accents[5],
            UserRole.teacher => context.accents.accents[3],
            UserRole.student => context.accents.accents[0],
          }
        : context.status.neutral;

    return Card(
      child: ListTile(
        key: Key('user_${user.id}'),
        // Colour by role, so a directory of sixty is scannable. A deactivated account
        // drops to neutral: the role still shows, but the row reads as switched off.
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: roleColour.container,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            switch (user.role) {
              UserRole.admin => Icons.shield_outlined,
              UserRole.teacher => Icons.school_outlined,
              UserRole.student => Icons.person_outline,
            },
            size: 20,
            color: roleColour.foreground,
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
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    key: Key('user_active_${user.id}'),
                    value: user.isActive,
                    onChanged: (value) => _setActive(user, value),
                  ),
                  // Only once the account is switched off. Deactivating is the
                  // reversible version of the same intent, so it comes first and this
                  // never appears beside a live account.
                  if (!user.isActive)
                    IconButton(
                      key: Key('delete_user_${user.id}'),
                      tooltip: 'Delete account',
                      onPressed: () => _confirmDelete(user),
                      icon: Icon(
                        Icons.delete_outline,
                        color: context.status.danger.foreground,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Creating an account. The role decides which profile fields the API requires, so the
/// form asks for exactly those and no more.
class _NewUserDialog extends ConsumerStatefulWidget {
  const _NewUserDialog();

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
  int? _studyYear;
  int? _semester;
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
    final isStudentRole = _role == UserRole.student;
    try {
      await ref.read(adminRepositoryProvider).createUser(
            userId: _userId.text.trim(),
            password: _password.text,
            name: _name.text.trim(),
            role: _role,
            email: email.isEmpty ? null : email,
            departmentId: _departmentId,
            // A student's login *is* their student number, so the form asks once and
            // sends it for both. Sent explicitly rather than left for the server to
            // default: the app already knows the value, and relying on the server to
            // fill it in means the form breaks against any deployment that has not
            // caught up yet -- which is exactly what happened.
            studentId: _role == UserRole.student ? _userId.text.trim() : null,
            studyYear: isStudentRole ? _studyYear : null,
            semester: isStudentRole ? _semester : null,
            teacherId: _role == UserRole.teacher
                ? (profileId.isEmpty ? null : profileId)
                : null,
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
    final isStudent = _role == UserRole.student;
    // Watched, not read: `ref.read` on a provider nobody has subscribed to returns
    // AsyncLoading with no value, so the previous version handed this dialog an empty
    // list every single time and the picker could never show anything. Watching starts
    // the fetch and rebuilds when it lands.
    final departments = ref.watch(departmentsProvider);

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
                  keyboardType:
                      isStudent ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: isStudent ? 'Student ID' : 'Login ID',
                    helperText: isStudent
                        ? '8 digits — this is what they sign in with'
                        : 'What they type to sign in',
                  ),
                  validator: (value) {
                    final entered = value?.trim() ?? '';
                    if (isStudent) {
                      // Caught here as well as on the server: a mistyped roll number
                      // otherwise becomes an account nobody can sign in to.
                      return RegExp(r'^\d{8}$').hasMatch(entered)
                          ? null
                          : 'A student ID is exactly 8 digits';
                    }
                    return entered.length < 3 ? 'At least 3 characters' : null;
                  },
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
                    helperText:
                        'At least 8 characters. Give it to them; they can change it after signing in.',
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
                if (_role == UserRole.teacher) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('new_user_profile_id'),
                    controller: _roleId,
                    decoration: const InputDecoration(
                      labelText: 'Staff ID (optional)',
                      helperText: 'Defaults to the login ID',
                    ),
                  ),
                ],
                if (isStudent) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          key: const Key('new_user_year'),
                          isExpanded: true,
                          initialValue: _studyYear,
                          decoration: const InputDecoration(labelText: 'Year'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Not set'),
                            ),
                            for (var n = 1; n <= 4; n++)
                              DropdownMenuItem<int?>(
                                value: n,
                                child: Text(ordinalYear(n)),
                              ),
                          ],
                          onChanged: (value) => setState(() => _studyYear = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          key: const Key('new_user_semester'),
                          isExpanded: true,
                          initialValue: _semester,
                          decoration: const InputDecoration(labelText: 'Semester'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Not set'),
                            ),
                            for (var n = 1; n <= 2; n++)
                              DropdownMenuItem<int?>(
                                value: n,
                                child: Text(ordinalSemester(n)),
                              ),
                          ],
                          onChanged: (value) => setState(() => _semester = value),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                departments.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                  // The field is optional, so a list that will not load must not block
                  // the form -- but say so rather than showing an empty picker, which
                  // reads as "there are no departments".
                  error: (_, _) => const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.warning_amber_outlined),
                    title: Text('Departments could not be loaded'),
                    subtitle: Text('You can create the account and set it later.'),
                  ),
                  data: (items) => DropdownButtonFormField<int?>(
                    key: const Key('new_user_department'),
                    initialValue: _departmentId,
                    // Without this the menu sizes to its widest item and overflows the
                    // dialog: "CSE — Computer Science & Engineering" is longer than the
                    // field it sits in.
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Department',
                      helperText: items.isEmpty ? 'No departments exist yet' : null,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('None')),
                      for (final department in items)
                        DropdownMenuItem<int?>(
                          value: department.id,
                          child: Text(
                            '${department.code} — ${department.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _departmentId = value),
                  ),
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
