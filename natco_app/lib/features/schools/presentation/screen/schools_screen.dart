/// Schools screen.
///
/// Implemented in Phase 2 - Master Data; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class SchoolsScreen extends StatelessWidget {
  const SchoolsScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Schools',
    phase: 'Phase 2 - Master Data',
    icon: Icons.account_tree_outlined,
    summary: 'Browse the State, District, Cluster and School hierarchy, restricted to your assigned area. Values are chosen from master-data selectors, never typed freely.',
    capabilities: <String>[
      'State, district, cluster and school records with stable identifiers',
      'Search and filter with paginated lists, so a large district never loads at once',
      'Scope-restricted browsing: you see only the schools you are responsible for',
    ],
  );
}
