/// Scanner calibration screen.
///
/// Implemented in Phase 6 - OMR Engine; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Scanner calibration',
    phase: 'Phase 6 - OMR Engine',
    icon: Icons.tune_outlined,
    summary: 'Admin-only calibration: run the scanner against test sheets with known answers, see measured accuracy, and adjust thresholds. Teachers cannot change scanner thresholds.',
    capabilities: <String>[
      'Upload or pick a test OMR and run the current or a draft threshold set',
      'Comparison against ground truth, per question',
      'Measured accuracy for the batch, including the silent error rate',
      'Threshold changes recorded in the audit log',
    ],
  );
}
