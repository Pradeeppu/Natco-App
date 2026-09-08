/// Validate sheet screen.
///
/// Implemented in Phase 7 - Validation; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class OmrValidationScreen extends StatelessWidget {
  const OmrValidationScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Validate sheet',
    phase: 'Phase 7 - Validation',
    icon: Icons.fact_check_outlined,
    summary: 'Human validation, question by question. The machine reading is preserved exactly as it was; the validator records a separate final answer.',
    capabilities: <String>[
      'Cropped bubble image for the question under review',
      'Choice of A, B, C, D, Blank or Multiple',
      'Machine answer and confidence shown but never overwritten',
      'Validator, timestamp and reason recorded on every decision',
    ],
  );
}
