import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Departments. Administrator only — the API refuses writes from anyone else.
///
/// There is no delete: courses, users and profiles all point at a department, and
/// removing one would strand them. Deactivating keeps the record and its history while
/// taking it out of the pickers, which is what "we no longer use this" actually means.
class DepartmentsScreen extends ConsumerStatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  ConsumerState<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends ConsumerState<DepartmentsScreen> {
  int? _busyId;

  Future<void> _create() async {
    final result = await showDialog<({String code, String name})>(
      context: context,
      builder: (_) => const _DepartmentDialog(),
    );
    if (result == null) return;
    try {
      await ref
          .read(departmentRepositoryProvider)
          .create(code: result.code, name: result.name);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) ref.invalidate(departmentsProvider);
    }
  }

  Future<void> _rename(Department department) async {
    final result = await showDialog<({String code, String name})>(
      context: context,
      builder: (_) => _DepartmentDialog(existing: department),
    );
    if (result == null) return;
    setState(() => _busyId = department.id);
    try {
      await ref.read(departmentRepositoryProvider).update(
            department.id,
            name: result.name,
          );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
        ref.invalidate(departmentsProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Departments')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_department'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: departments.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message:
              error is ApiException ? error.message : 'Could not load the departments.',
          onRetry: () => ref.invalidate(departmentsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No departments yet',
              subtitle: 'Create one so courses and users can be filed under it.',
              icon: Icons.apartment_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) => _tile(items[index]),
          );
        },
      ),
    );
  }

  Widget _tile(Department department) {
    final busy = _busyId == department.id;
    final tint = department.isActive
        ? context.accents.forKey(department.code)
        : context.status.neutral;

    return Card(
      child: ListTile(
        key: Key('department_${department.id}'),
        // Its own colour, from the same palette courses draw on, so a department and
        // the courses under it are recognisably related rather than uniformly grey.
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.container,
            borderRadius: BorderRadius.circular(12),
          ),
          // An icon rather than the code: the subtitle already carries the code, and
          // printing it twice in one row helps nobody.
          child: Icon(Icons.apartment_rounded, size: 20, color: tint.foreground),
        ),
        title: Text(department.name),
        subtitle: Text(
          department.code,
        ),
        trailing: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: InlineLoader(size: 20),
              )
            : IconButton(
                key: Key('department_rename_${department.id}'),
                tooltip: 'Rename',
                onPressed: () => _rename(department),
                icon: const Icon(Icons.edit_outlined),
              ),
      ),
    );
  }
}

class _DepartmentDialog extends StatefulWidget {
  const _DepartmentDialog({this.existing});

  final Department? existing;

  @override
  State<_DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<_DepartmentDialog> {
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return AlertDialog(
      title: Text(editing ? 'Rename department' : 'New department'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('department_code'),
            controller: _code,
            // Fixed once created: other records refer to the department by it.
            readOnly: editing,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Code',
              helperText: editing ? 'The code cannot be changed' : 'For example CSE',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('department_name'),
            controller: _name,
            autofocus: editing,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('department_submit'),
          onPressed: () {
            final code = _code.text.trim();
            final name = _name.text.trim();
            if (code.isEmpty || name.isEmpty) return;
            Navigator.of(context).pop((code: code, name: name));
          },
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
