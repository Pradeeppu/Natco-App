/// School screen.
///
/// Implemented in Phase 2 - Master Data; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class SchoolDetailScreen extends StatelessWidget {
  const SchoolDetailScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'School',
    phase: 'Phase 2 - Master Data',
    icon: Icons.school_outlined,
    summary: 'A single school: its place in the hierarchy, the grades it teaches, its students, and its assessment progress.',
    capabilities: <String>[
      'School profile with its cluster, district and state ancestry',
      'Grade and section breakdown',
      'Assessment assignments and completion for this school',
    ],
  );
}
