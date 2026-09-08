/// Analytics screen.
///
/// Implemented in Phase 10 - Analytics; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Analytics',
    phase: 'Phase 10 - Analytics',
    icon: Icons.insights_outlined,
    summary: 'Drill-down analytics from state to student, plus question-level performance. Figures come from server-side rollups, not from a phone summing thousands of rows.',
    capabilities: <String>[
      'Drill-down through state, district, cluster, school, grade, section and student',
      'Completion, capture, processing and validation counts',
      'Question-level correct percentages, with the hardest and easiest questions',
      'High blank-rate and high multiple-mark-rate questions',
    ],
  );
}
