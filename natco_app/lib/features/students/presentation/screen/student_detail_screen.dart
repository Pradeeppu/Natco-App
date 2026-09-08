/// Student screen.
///
/// Implemented in Phase 2 - Master Data; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class StudentDetailScreen extends StatelessWidget {
  const StudentDetailScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Student',
    phase: 'Phase 2 - Master Data',
    icon: Icons.person_outline,
    summary: 'One student: their enrollment history, and their results once scoring is in place.',
    capabilities: <String>[
      'Student profile and enrollment per academic year',
      'Assessment history within your scope',
      'Question-level review, with the original OMR image where your role permits it',
    ],
  );
}
