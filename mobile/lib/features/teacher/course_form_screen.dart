import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Creating a course, or editing one you own.
///
/// The course code is fixed after creation: it is what enrolments, exams and results
/// are filed under, and the API does not accept a change to it. The field is shown
/// read-only when editing rather than hidden, so the code stays legible.
class CourseFormScreen extends ConsumerStatefulWidget {
  const CourseFormScreen({super.key, this.courseId});

  /// Null when creating.
  final int? courseId;

  bool get isEditing => courseId != null;

  @override
  ConsumerState<CourseFormScreen> createState() => _CourseFormScreenState();
}

class _CourseFormScreenState extends ConsumerState<CourseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _session = TextEditingController();

  int? _departmentId;
  int? _semester;
  bool _isActive = true;
  bool _saving = false;
  bool _loaded = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _session.dispose();
    super.dispose();
  }

  void _fill(Course course) {
    if (_loaded) return;
    _loaded = true;
    _code.text = course.courseCode;
    _name.text = course.courseName;
    _session.text = course.session ?? '';
    _departmentId = course.departmentId;
    _semester = course.semester;
    _isActive = course.isActive;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(courseRepositoryProvider);
    final session = _session.text.trim();
    try {
      if (widget.isEditing) {
        await repository.update(
          widget.courseId!,
          courseName: _name.text.trim(),
          departmentId: _departmentId,
          semester: _semester,
          session: session.isEmpty ? null : session,
          isActive: _isActive,
        );
        refreshCourse(ref, widget.courseId!);
      } else {
        await repository.create(
          courseCode: _code.text.trim(),
          courseName: _name.text.trim(),
          departmentId: _departmentId,
          semester: _semester,
          session: session.isEmpty ? null : session,
        );
        ref.invalidate(courseProvider);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsProvider);

    if (widget.isEditing && !_loaded) {
      final course = ref.watch(courseDetailProvider(widget.courseId!));
      return course.when(
        loading: () => const Scaffold(body: LoadingView()),
        error: (error, _) => Scaffold(
          appBar: AppBar(title: const Text('Edit Course')),
          body: ErrorView(
            message: error is ApiException ? error.message : 'Could not load this course.',
            onRetry: () => ref.invalidate(courseDetailProvider(widget.courseId!)),
          ),
        ),
        data: (data) {
          _fill(data);
          return _form(context, departments);
        },
      );
    }
    return _form(context, departments);
  }

  Widget _form(BuildContext context, AsyncValue<List<Department>> departments) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit Course' : 'New Course')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('course_code'),
              controller: _code,
              readOnly: widget.isEditing,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Course code',
                prefixIcon: const Icon(Icons.tag),
                helperText: widget.isEditing
                    ? 'The code cannot be changed once the course exists'
                    : 'For example CSE-301',
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Enter a course code' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('course_name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Course name',
                prefixIcon: Icon(Icons.book_outlined),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Enter a course name' : null,
            ),
            const SizedBox(height: 16),
            departments.when(
              loading: () => const LinearProgressIndicator(),
              // A missing department list must not block the form: the field is optional,
              // so the course can still be saved without one.
              error: (_, _) => const ListTile(
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('Departments could not be loaded'),
                subtitle: Text('You can save without one and set it later.'),
              ),
              data: (items) => DropdownButtonFormField<int?>(
                key: const Key('course_department'),
                initialValue: _departmentId,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  prefixIcon: Icon(Icons.apartment_outlined),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None')),
                  for (final department in items)
                    DropdownMenuItem<int?>(
                      value: department.id,
                      child: Text('${department.code} — ${department.name}'),
                    ),
                ],
                onChanged: (value) => setState(() => _departmentId = value),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              key: const Key('course_semester'),
              initialValue: _semester,
              decoration: const InputDecoration(
                labelText: 'Semester',
                prefixIcon: Icon(Icons.calendar_view_month_outlined),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
                for (var n = 1; n <= 12; n++)
                  DropdownMenuItem<int?>(value: n, child: Text('Semester $n')),
              ],
              onChanged: (value) => setState(() => _semester = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('course_session'),
              controller: _session,
              decoration: const InputDecoration(
                labelText: 'Session',
                prefixIcon: Icon(Icons.date_range_outlined),
                helperText: 'For example 2025-2026',
              ),
            ),
            if (widget.isEditing) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('course_active'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Active'),
                subtitle: const Text(
                  'An archived course keeps its exams and results, and stops appearing '
                  'in the active list.',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  key: const Key('course_error'),
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('course_save'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(widget.isEditing ? 'Save changes' : 'Create course'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
