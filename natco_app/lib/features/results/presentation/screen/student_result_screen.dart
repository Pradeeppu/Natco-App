/// Student result screen.
///
/// Implemented in Phase 8 - Scoring; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class StudentResultScreen extends StatelessWidget {
  const StudentResultScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Student result',
    phase: 'Phase 8 - Scoring',
    icon: Icons.assessment_outlined,
    summary: 'One student\'s result for one assessment, down to the individual question.',
    capabilities: <String>[
      'Total marks, marks obtained and percentage',
      'Per-question detected answer, final answer, correctness and marks',
      'The original OMR image where your role permits it',
    ],
  );
}
