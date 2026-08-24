import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uniexam/core/api_exception.dart';
import 'package:uniexam/features/student/widgets/student_exam_tile.dart';
import 'package:uniexam/features/teacher/widgets/exam_tile.dart';
import 'package:uniexam/models/join_request.dart';
import 'package:uniexam/providers/exam_provider.dart';
import 'package:uniexam/providers/providers.dart';
import 'package:uniexam/widgets/status_views.dart';

/// Who has asked to sit this exam, and the teacher's decision.
class JoinRequestsScreen extends ConsumerStatefulWidget {
  const JoinRequestsScreen({super.key, required this.examId});

  final int examId;

  @override
  ConsumerState<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends ConsumerState<JoinRequestsScreen> {
  int? _busyRequestId;
  bool _bulkBusy = false;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) ref.invalidate(joinRequestsProvider(widget.examId));
    }
  }

  Future<void> _review(JoinRequest request, {required bool approve}) async {
    setState(() => _busyRequestId = request.id);
    await _run(() async {
      final repository = ref.read(examRepositoryProvider);
      if (approve) {
        await repository.approveRequest(request.id);
      } else {
        await repository.rejectRequest(request.id);
      }
    });
    if (mounted) setState(() => _busyRequestId = null);
  }

  Future<void> _reviewAll(List<JoinRequest> pending, {required bool approve}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve all pending?' : 'Reject all pending?'),
        content: Text(
          '${pending.length} request${pending.length == 1 ? '' : 's'} will be '
          '${approve ? 'approved' : 'rejected'} together.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(approve ? 'Approve all' : 'Reject all'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _bulkBusy = true);
    await _run(() async {
      await ref.read(examRepositoryProvider).reviewAll(
            widget.examId,
            approve: approve,
            // Only the requests on screen: one that arrived since the list loaded is
            // left for the teacher to look at rather than swept up unseen.
            requestIds: pending.map((request) => request.id).toList(),
          );
    });
    if (mounted) setState(() => _bulkBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(joinRequestsProvider(widget.examId));

    return Scaffold(
      appBar: AppBar(title: const Text('Join Requests')),
      body: requests.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load the requests.',
          onRetry: () => ref.invalidate(joinRequestsProvider(widget.examId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'No requests yet',
              subtitle: 'Students enrolled in this course can ask to sit the exam once '
                  'it is published.',
              icon: Icons.how_to_reg_outlined,
            );
          }
          final pending = items.where((request) => request.isPending).toList();
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(joinRequestsProvider(widget.examId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (pending.isNotEmpty) _bulkBar(pending),
                for (final request in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _requestCard(request),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bulkBar(List<JoinRequest> pending) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${pending.length} pending',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton(
            key: const Key('reject_all'),
            onPressed: _bulkBusy ? null : () => _reviewAll(pending, approve: false),
            child: const Text('Reject all'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('approve_all'),
            onPressed: _bulkBusy ? null : () => _reviewAll(pending, approve: true),
            child: const Text('Approve all'),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(JoinRequest request) {
    final theme = Theme.of(context);
    final busy = _busyRequestId == request.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.student.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        request.student.studentNumber ?? request.student.userId,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                JoinStatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Asked ${formatDateTime(request.requestedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (request.isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: Key('reject_${request.id}'),
                    onPressed: busy ? null : () => _review(request, approve: false),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: Key('approve_${request.id}'),
                    onPressed: busy ? null : () => _review(request, approve: true),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
