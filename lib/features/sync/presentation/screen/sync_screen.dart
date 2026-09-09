/// The sync queue: what is waiting to upload, what failed, what conflicts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/widgets/preview_kit.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/presentation/controller/sync_controller.dart';

final class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;

    final AsyncValue<List<SyncQueueEntry>> queueAsync =
        ref.watch(syncQueueProvider);
    final AppUser? user = ref.watch(sessionProvider).session?.user;
    
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: queueAsync.when(
        data: (List<SyncQueueEntry> entries) => _buildBody(context, ref, entries, user, theme, status),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, List<SyncQueueEntry> entries, AppUser user, ThemeData theme, NatcoStatusColors status) {
    final int syncedCount = entries.where((e) => e.status == SyncStatus.synced).length;
    final int pendingCount = entries.where((e) => e.status == SyncStatus.pending || e.status == SyncStatus.uploading).length;
    final int failedCount = entries.where((e) => e.status == SyncStatus.failed).length;
    final int conflictsCount = entries.where((e) => e.status == SyncStatus.conflict).length;

    final List<SyncQueueEntry> queueEntries = entries.where((e) => e.status != SyncStatus.synced && e.status != SyncStatus.conflict).toList();
    final List<SyncQueueEntry> conflictEntries = entries.where((e) => e.status == SyncStatus.conflict).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PreviewMetricRow(
          metrics: <PreviewMetric>[
            PreviewMetric(
              label: 'Synced',
              value: syncedCount.toString(),
              tone: status.success,
            ),
            PreviewMetric(label: 'Pending', value: pendingCount.toString()),
            PreviewMetric(label: 'Failed', value: failedCount.toString(), tone: status.danger),
            PreviewMetric(
              label: 'Conflicts',
              value: conflictsCount.toString(),
              tone: status.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: status.successContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Icon(Icons.shield_outlined, color: status.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Everything below is already saved on this device. '
                    'Nothing is lost if the app closes or the battery dies.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: status.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        PreviewSection(
          title: 'Queue',
          action: TextButton.icon(
            onPressed: () => ref.read(syncControllerProvider.notifier).retryFailed(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry failed'),
          ),
          child: PreviewListCard(
            children: previewDivided(
              queueEntries.map((SyncQueueEntry e) => _buildQueueListTile(e, theme)).toList(growable: false),
            ),
          ),
        ),
        if (conflictEntries.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Conflict waiting on you', style: theme.textTheme.titleMedium),
          Text('Never resolved automatically', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          ...conflictEntries.map((e) => _buildConflictCard(context, ref, e, user, theme)),
        ]
      ],
    );
  }

  Widget _buildQueueListTile(SyncQueueEntry e, ThemeData theme) {
    StatusTone tone;
    switch (e.status) {
      case SyncStatus.pending:
        tone = StatusTone.neutral;
      case SyncStatus.uploading:
        tone = StatusTone.pending;
      case SyncStatus.failed:
        tone = StatusTone.danger;
      default:
        tone = StatusTone.neutral;
    }

    final bool isFailed = e.status == SyncStatus.failed;

    return ListTile(
      isThreeLine: isFailed,
      title: Text('${e.entityType} ${e.entityId}'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          isFailed
              ? '${e.operation}\n${e.errorMessage ?? 'Unknown error'} · ${e.attemptCount} attempts'
              : e.operation,
          style: theme.textTheme.bodySmall,
        ),
      ),
      trailing: StatusChip(label: e.status.wireName, tone: tone),
    );
  }

  Widget _buildConflictCard(BuildContext context, WidgetRef ref, SyncQueueEntry e, AppUser user, ThemeData theme) {
    final SyncController controller = ref.read(syncControllerProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${e.entityType} ${e.entityId}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              e.errorMessage ?? 'A conflict occurred.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => controller.keepServer(e, user.userId, user.role.wireName),
                    child: const Text('Keep server'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => controller.keepLocal(e, user.userId, user.role.wireName),
                    child: const Text('Keep local'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => controller.createReviewCase(e, user.userId, user.role.wireName),
              child: const Text('Create a review case'),
            ),
          ],
        ),
      ),
    );
  }
}
