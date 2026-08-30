import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/models/enrolment_candidate.dart';
import 'package:uniexam/models/study_stage.dart';
import 'package:uniexam/providers/course_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Put a whole cohort on a course's roll.
///
/// Enrolling a year group by typing student ids one at a time is the kind of work
/// software exists to remove. Pick the year and the half of it, see who is there, tick
/// the ones you want or take the lot.
class AddStudentsScreen extends ConsumerStatefulWidget {
  const AddStudentsScreen({super.key, required this.courseId});

  final int courseId;

  @override
  ConsumerState<AddStudentsScreen> createState() => _AddStudentsScreenState();
}

class _AddStudentsScreenState extends ConsumerState<AddStudentsScreen> {
  final _search = TextEditingController();

  int? _year;
  int? _semester;
  String? _query;

  bool _loading = true;
  bool _adding = false;
  String? _error;
  EnrolmentCandidates? _candidates;

  /// Ticked rows, by login id — which is what the bulk enrol endpoint takes.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await ref.read(courseRepositoryProvider).enrolmentCandidates(
            widget.courseId,
            studyYear: _year,
            semester: _semester,
            search: _query,
          );
      if (!mounted) return;
      setState(() {
        _candidates = found;
        // A selection made against the previous filter would enrol people who are no
        // longer on screen, so it does not survive one.
        _selected.retainWhere(
          (id) => found.items.any((candidate) => candidate.userId == id),
        );
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _add(List<String> userIds) async {
    if (userIds.isEmpty) return;
    setState(() => _adding = true);
    try {
      final result = await ref
          .read(courseRepositoryProvider)
          .enrollBulk(widget.courseId, userIds);
      refreshCourse(ref, widget.courseId);
      if (!mounted) return;

      final skipped = result.skipped.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped == 0
                ? '${result.enrolled.length} added to the roll'
                : '${result.enrolled.length} added, $skipped skipped',
          ),
        ),
      );
      _selected.clear();
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _candidates?.items ?? const <EnrolmentCandidate>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Add students')),
      body: Column(
        children: [
          _Filters(
            year: _year,
            semester: _semester,
            search: _search,
            onYear: (value) {
              setState(() => _year = value);
              _load();
            },
            onSemester: (value) {
              setState(() => _semester = value);
              _load();
            },
            onSearch: (value) {
              final trimmed = value.trim();
              setState(() => _query = trimmed.isEmpty ? null : trimmed);
              _load();
            },
          ),
          const Divider(height: 1),
          Expanded(child: _body(items)),
        ],
      ),
      bottomNavigationBar: items.isEmpty || _loading
          ? null
          : _ActionBar(
              selected: _selected.length,
              total: items.length,
              truncated: _candidates?.truncated ?? false,
              busy: _adding,
              onAddSelected: () => _add(_selected.toList()),
              onAddAll: () => _add([for (final c in items) c.userId]),
            ),
    );
  }

  Widget _body(List<EnrolmentCandidate> items) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (items.isEmpty) {
      return EmptyView(
        title: 'Nobody left to add',
        subtitle: _year == null && _query == null
            ? 'Every student in this department is already on the roll.'
            : 'No student matches this filter who is not already enrolled.',
        icon: Icons.groups_outlined,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, index) {
        final candidate = items[index];
        final ticked = _selected.contains(candidate.userId);
        return CheckboxListTile(
          key: Key('candidate_${candidate.userId}'),
          value: ticked,
          onChanged: _adding
              ? null
              : (value) => setState(() {
                    if (value ?? false) {
                      _selected.add(candidate.userId);
                    } else {
                      _selected.remove(candidate.userId);
                    }
                  }),
          secondary: CircleAvatar(
            backgroundColor: context.accents.forKey(candidate.userId).container,
            child: Text(
              _initials(candidate.name),
              style: TextStyle(
                color: context.accents.forKey(candidate.userId).foreground,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          title: Text(candidate.name),
          subtitle: Text(
            [
              candidate.studentId ?? candidate.userId,
              if (candidate.stage != null) candidate.stage!,
              if (candidate.session != null) candidate.session!,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.year,
    required this.semester,
    required this.search,
    required this.onYear,
    required this.onSemester,
    required this.onSearch,
  });

  final int? year;
  final int? semester;
  final TextEditingController search;
  final ValueChanged<int?> onYear;
  final ValueChanged<int?> onSemester;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  key: const Key('candidate_year'),
                  isExpanded: true,
                  initialValue: year,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Any year')),
                    for (var n = 1; n <= 4; n++)
                      DropdownMenuItem<int?>(value: n, child: Text(ordinalYear(n))),
                  ],
                  onChanged: onYear,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  key: const Key('candidate_semester'),
                  isExpanded: true,
                  initialValue: semester,
                  decoration: const InputDecoration(
                    labelText: 'Semester',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Both')),
                    for (var n = 1; n <= 2; n++)
                      DropdownMenuItem<int?>(value: n, child: Text(ordinalSemester(n))),
                  ],
                  onChanged: onSemester,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('candidate_search'),
            controller: search,
            decoration: InputDecoration(
              hintText: 'Search by name or student ID',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        search.clear();
                        onSearch('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onSubmitted: onSearch,
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.selected,
    required this.total,
    required this.truncated,
    required this.busy,
    required this.onAddSelected,
    required this.onAddAll,
  });

  final int selected;
  final int total;
  final bool truncated;
  final bool busy;
  final VoidCallback onAddSelected;
  final VoidCallback onAddAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (truncated)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  // Never let "all" mean something different from what is on screen.
                  'Showing the first $total. Narrow the filter to see the rest.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('add_selected_students'),
                    onPressed: busy || selected == 0 ? null : onAddSelected,
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(selected == 0 ? 'Add selected' : 'Add $selected'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('add_all_students'),
                    onPressed: busy ? null : onAddAll,
                    icon: busy
                        ? const InlineLoader(size: 18)
                        : const Icon(Icons.group_add_outlined),
                    label: Text(busy ? 'Adding...' : 'Add all $total'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
