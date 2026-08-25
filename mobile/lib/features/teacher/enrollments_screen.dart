import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/enrollment.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// The roll for one course: who is on it, and how to change that.
class EnrollmentsScreen extends ConsumerStatefulWidget {
  const EnrollmentsScreen({super.key, required this.courseId});

  final int courseId;

  @override
  ConsumerState<EnrollmentsScreen> createState() => _EnrollmentsScreenState();
}

class _EnrollmentsScreenState extends ConsumerState<EnrollmentsScreen> {
  bool _busy = false;
  int? _removing;

  Future<void> _addOne() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enrol a student'),
        content: TextField(
          key: const Key('single_student_id'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Student ID',
            helperText: 'The ID the student signs in with',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Enrol'),
          ),
        ],
      ),
    );
    if (id == null || id.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(courseRepositoryProvider).enroll(widget.courseId, id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Enrolled $id.')));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(enrollmentsProvider(widget.courseId));
      }
    }
  }

  Future<void> _addMany() async {
    final ids = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _BulkEnrolDialog(),
    );
    if (ids == null || ids.isEmpty) return;

    setState(() => _busy = true);
    try {
      final result =
          await ref.read(courseRepositoryProvider).enrollBulk(widget.courseId, ids);
      if (mounted) await _showBulkOutcome(result);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(enrollmentsProvider(widget.courseId));
      }
    }
  }

  /// Shows what the batch did, name by name.
  ///
  /// A count alone would leave a teacher comparing two lists by eye to find the one
  /// id that failed, which is exactly the work the batch was meant to save.
  Future<void> _showBulkOutcome(BulkEnrolmentResult result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('bulk_outcome'),
        title: Text('Enrolled ${result.enrolledCount}'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (result.skipped.isEmpty)
                const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Every ID on the list was enrolled.'),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '${result.skippedCount} could not be enrolled',
                    style: Theme.of(dialogContext).textTheme.titleSmall,
                  ),
                ),
                for (final skip in result.skipped)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.error_outline),
                    title: Text(skip.studentUserId),
                    subtitle: Text(skip.reason.label),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(Enrollment enrollment) async {
    final name = enrollment.student?.name ?? 'this student';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from course?'),
        content: Text(
          '$name will lose access to this course and its exams. Any results they '
          'already have are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _removing = enrollment.studentId);
    try {
      await ref
          .read(courseRepositoryProvider)
          .unenroll(widget.courseId, enrollment.studentId);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _removing = null);
        ref.invalidate(enrollmentsProvider(widget.courseId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roll = ref.watch(enrollmentsProvider(widget.courseId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enrolled Students'),
        actions: [
          IconButton(
            key: const Key('bulk_enrol'),
            tooltip: 'Enrol a list',
            onPressed: _busy ? null : _addMany,
            icon: const Icon(Icons.playlist_add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('enrol_one'),
        onPressed: _busy ? null : _addOne,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Enrol'),
      ),
      body: roll.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load the roll.',
          onRetry: () => ref.invalidate(enrollmentsProvider(widget.courseId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'Nobody is enrolled yet',
              subtitle: 'Enrol students one at a time, or paste a whole roll list with '
                  'the button in the top bar.',
              icon: Icons.group_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(enrollmentsProvider(widget.courseId).future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${items.length} enrolled',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  );
                }
                return _tile(items[index - 1]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _tile(Enrollment enrollment) {
    final theme = Theme.of(context);
    final student = enrollment.student;
    final busy = _removing == enrollment.studentId;

    return Card(
      child: ListTile(
        // Each student their own tint, keyed on the ID, so a roll of sixty reads as
        // sixty people rather than one row repeated.
        leading: Builder(builder: (context) {
          final tint = context.accents.forKey(student?.userId ?? '${enrollment.studentId}');
          return Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.container,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _initials(student?.name),
              style: theme.textTheme.labelMedium?.copyWith(
                color: tint.foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }),
        title: Text(student?.name ?? 'Student #${enrollment.studentId}'),
        subtitle: Text(student?.userId ?? 'ID unavailable'),
        trailing: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : IconButton(
                key: Key('remove_${enrollment.studentId}'),
                tooltip: 'Remove from course',
                onPressed: () => _remove(enrollment),
                icon: const Icon(Icons.person_remove_outlined),
              ),
      ),
    );
  }
}

/// Collects a roll list. Splits on whatever the source used — newlines, commas, spaces —
/// because a list pasted out of a spreadsheet or an email rarely arrives tidy.
class _BulkEnrolDialog extends StatefulWidget {
  const _BulkEnrolDialog();

  @override
  State<_BulkEnrolDialog> createState() => _BulkEnrolDialogState();
}

class _BulkEnrolDialogState extends State<_BulkEnrolDialog> {
  final _controller = TextEditingController();
  List<String> _ids = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse(String raw) {
    final parts = raw
        .split(RegExp(r'[\s,;]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    // Collapse repeats here as well as on the server, so the count shown before
    // sending matches what will actually be attempted.
    setState(() => _ids = parts.toSet().toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    const limit = 200;
    final tooMany = _ids.length > limit;

    return AlertDialog(
      title: const Text('Enrol a roll list'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste student IDs separated by new lines, commas or spaces.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('bulk_ids'),
              controller: _controller,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              onChanged: _parse,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '20261234\n20261235\n20261236',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tooMany
                  ? '${_ids.length} IDs — at most $limit per batch'
                  : '${_ids.length} ID${_ids.length == 1 ? '' : 's'} ready',
              key: const Key('bulk_count'),
              style: TextStyle(
                color: tooMany ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('bulk_submit'),
          onPressed: _ids.isEmpty || tooMany ? null : () => Navigator.of(context).pop(_ids),
          child: const Text('Enrol'),
        ),
      ],
    );
  }
}

/// Two letters is enough to recognise a name you already know.
String _initials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}
