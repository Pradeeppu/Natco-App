/// Assessment session screen.
///
/// Implemented in Phase 4 - Offline Assessment; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class AssessmentSessionScreen extends StatelessWidget {
  const AssessmentSessionScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Assessment session',
    phase: 'Phase 4 - Offline Assessment',
    icon: Icons.play_circle_outline,
    summary: 'A live assessment session for one school, grade and section. Runs entirely offline and survives the app being killed.',
    capabilities: <String>[
      'Session lifecycle from draft to closed, with rejected illegal transitions',
      'Student roster pre-downloaded for the assigned grade and section',
      'Local-first writes, so nothing depends on a connection',
      'Recovery on restart, with no silent data loss',
    ],
  );
}
