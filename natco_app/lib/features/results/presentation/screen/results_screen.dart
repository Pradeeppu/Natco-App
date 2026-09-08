/// Results screen.
///
/// Implemented in Phase 8 - Scoring; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Results',
    phase: 'Phase 8 - Scoring',
    icon: Icons.grading_outlined,
    summary: 'Scored results for your area, with question-level detail.',
    capabilities: <String>[
      'Result lists by assessment, school, grade and section',
      'Marks, percentage, and counts of correct, incorrect and blank answers',
      'The answer-key version each result was scored against',
    ],
  );
}
