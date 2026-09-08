/// Sync screen.
///
/// Implemented in Phase 9 - Synchronization; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Sync',
    phase: 'Phase 9 - Synchronization',
    icon: Icons.sync_outlined,
    summary: 'The state of this device\'s upload queue: what is pending, what failed and why, and what is waiting on a decision. Nothing is ever discarded.',
    capabilities: <String>[
      'Pending, uploading, synced, failed and conflicted counts',
      'Failed entries named by what they are, not by an opaque identifier',
      'Retry Failed Uploads, and idempotent retries that cannot duplicate a record',
      'Conflicts shown as local versus server, resolved only by a permitted role',
    ],
  );
}
