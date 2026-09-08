/// Scan result screen.
///
/// Implemented in Phase 6 - OMR Engine; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class OmrReviewScreen extends StatelessWidget {
  const OmrReviewScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Scan result',
    phase: 'Phase 6 - OMR Engine',
    icon: Icons.document_scanner_outlined,
    summary: 'The result of reading one sheet: detected answers, confidence per answer, and a score preview. Publication is blocked until any required validation is complete.',
    capabilities: <String>[
      'Per-question detected answer, confidence and status',
      'Counts of high, medium and low confidence answers, blanks and multiple marks',
      'Score preview against the answer-key version held on this device',
      'Duplicate detection against the OMR registry, showing the earlier submission',
      'No route to a final score while any answer still needs a human',
    ],
  );
}
