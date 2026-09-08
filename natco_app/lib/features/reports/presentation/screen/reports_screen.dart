/// Reports screen.
///
/// Implemented in Phase 11 - Reports; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Reports',
    phase: 'Phase 11 - Reports',
    icon: Icons.download_outlined,
    summary: 'CSV export of the nine report types, scoped to your assigned area. Every export is audited, and no student name appears in a filename.',
    capabilities: <String>[
      'Student result, school, cluster, district and assessment summaries',
      'Question analysis, OMR processing, validation and sync failure reports',
      'CSV first, with the export layer structured so PDF and Excel can be added cleanly',
    ],
  );
}
