/// Validation screen.
///
/// Implemented in Phase 7 - Validation; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class OmrValidationQueueScreen extends StatelessWidget {
  const OmrValidationQueueScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Validation',
    phase: 'Phase 7 - Validation',
    icon: Icons.rule_folder_outlined,
    summary: 'The queue of sheets with answers the scanner was not confident about, restricted to your assigned area.',
    capabilities: <String>[
      'Queue filtered by school, cluster, assessment and date',
      'Counts of answers awaiting review per sheet',
      'Exception review for unreadable sheets and missing evidence',
    ],
  );
}
