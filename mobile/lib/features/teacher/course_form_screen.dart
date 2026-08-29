import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/course.dart';
import 'package:uniexam/models/department.dart';
import 'package:uniexam/models/study_stage.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/admin_provider.dart';
import 'package:uniexam/providers/auth_provider.dart';
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
  int? _studyYear;
  int? _semester;
  bool _isActive = true;
  String? _teacherName;
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
    _studyYear = course.studyYear;
    _semester = course.semester;
    _isActive = course.isActive;
    _teacherName = course.teacherName;
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
          studyYear: _studyYear,
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
          studyYear: _studyYear,
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
    // Assignment is an administrative act, not an editorial one: a teacher does not
    // hand their own course to somebody else, so the field is not shown to them.
    final isAdmin = ref.watch(authProvider).user?.isAdmin ?? false;

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
                // Department names are long enough to overflow the field they sit in.
                isExpanded: true,
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
                      child: Text(
                        '${department.code} — ${department.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _departmentId = value),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    key: const Key('course_year'),
                    isExpanded: true,
                    initialValue: _studyYear,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
                      for (var n = 1; n <= 4; n++)
                        DropdownMenuItem<int?>(value: n, child: Text(ordinalYear(n))),
                    ],
                    onChanged: (value) => setState(() => _studyYear = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    key: const Key('course_semester'),
                    isExpanded: true,
                    initialValue: _semester,
                    decoration: const InputDecoration(labelText: 'Semester'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
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
            if (widget.isEditing && isAdmin) ...[
              const SizedBox(height: 20),
              _AssignTeacher(
                courseId: widget.courseId!,
                currentTeacher: _teacherName,
                onAssigned: (name, examsKept) {
                  setState(() => _teacherName = name);
                  refreshCourse(ref, widget.courseId!);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        examsKept == 0
                            ? '$name now runs this course.'
                            : '$name now runs this course. '
                                '$examsKept exam${examsKept == 1 ? '' : 's'} '
                                'stayed with the previous teacher, who wrote them.',
                      ),
                      duration: const Duration(seconds: 6),
                    ),
                  );
                },
              ),
            ],
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

/// Who runs this course, and the way to change it.
///
/// Shown to administrators on an existing course only. There is nothing to assign
/// before the course exists, and a teacher does not hand their own course away — that
/// is an administrative act, so it lives behind an administrative role.
class _AssignTeacher extends ConsumerStatefulWidget {
  const _AssignTeacher({
    required this.courseId,
    required this.currentTeacher,
    required this.onAssigned,
  });

  final int courseId;
  final String? currentTeacher;
  final void Function(String name, int examsKept) onAssigned;

  @override
  ConsumerState<_AssignTeacher> createState() => _AssignTeacherState();
}

class _AssignTeacherState extends ConsumerState<_AssignTeacher> {
  bool _busy = false;

  Future<void> _pick() async {
    final teachers = await ref.read(teachersProvider.future);
    if (!mounted) return;

    final chosen = await showDialog<User>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const Key('assign_teacher_dialog'),
        title: const Text('Who runs this course?'),
        children: [
          if (teachers.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text('No teacher accounts exist yet.'),
            ),
          for (final teacher in teachers)
            SimpleDialogOption(
              key: Key('assign_${teacher.userId}'),
              onPressed: () => Navigator.of(dialogContext).pop(teacher),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: dialogContext.status.info.container,
                  child: Icon(
                    Icons.school_outlined,
                    size: 20,
                    color: dialogContext.status.info.foreground,
                  ),
                ),
                title: Text(teacher.name),
                subtitle: Text(teacher.userId),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(courseRepositoryProvider)
          .assignTeacher(widget.courseId, chosen.userId);
      widget.onAssigned(chosen.name, result.examsKept);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assigned = widget.currentTeacher != null;
    final tint = assigned ? context.status.success : context.status.warning;

    return Card(
      child: ListTile(
        key: const Key('assign_teacher'),
        onTap: _busy ? null : _pick,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.container,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.school_outlined, size: 20, color: tint.foreground),
        ),
        title: const Text('Teacher in charge'),
        subtitle: Text(
          widget.currentTeacher ?? 'Nobody assigned yet',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tint.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: _busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.swap_horiz),
      ),
    );
  }
}
