/// Students screen.
///
/// Implemented in Phase 2 - Master Data; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class StudentsScreen extends StatelessWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Students',
    phase: 'Phase 2 - Master Data',
    icon: Icons.groups_outlined,
    summary: 'Student master data, managed centrally rather than re-entered for each assessment. Teachers see the students assigned to them.',
    capabilities: <String>[
      'Central student records with a stable internal student ID',
      'CSV import that reports rejected rows instead of merging duplicate children',
      'Duplicate prevention on school, name, grade, section and date of birth',
      'Paginated search, so a 2,000-student school scrolls rather than loading',
    ],
  );
}
