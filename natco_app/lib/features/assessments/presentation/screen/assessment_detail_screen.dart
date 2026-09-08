/// Assessment screen.
///
/// Implemented in Phase 3 - Assessments; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class AssessmentDetailScreen extends StatelessWidget {
  const AssessmentDetailScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Assessment',
    phase: 'Phase 3 - Assessments',
    icon: Icons.description_outlined,
    summary: 'A single assessment: its questions, its answer-key versions, and its assignments.',
    capabilities: <String>[
      'Question list with marks and option set',
      'Answer-key version history',
      'Assignments and expected OMR counts',
    ],
  );
}
