/// Assessments screen.
///
/// Implemented in Phase 3 - Assessments; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class AssessmentsScreen extends StatelessWidget {
  const AssessmentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Assessments',
    phase: 'Phase 3 - Assessments',
    icon: Icons.assignment_outlined,
    summary: 'Assessment definitions: questions, options, duration and the schools they are assigned to.',
    capabilities: <String>[
      'Assessment creation with a per-assessment option set, so new question types need no rewrite',
      'Question configuration and marks',
      'Assignment to schools, grades, sections and teachers',
      'Status lifecycle from draft through to closed',
    ],
  );
}
