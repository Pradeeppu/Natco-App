/// Answer key screen.
///
/// Implemented in Phase 3 - Assessments; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class AnswerKeyScreen extends StatelessWidget {
  const AnswerKeyScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Answer key',
    phase: 'Phase 3 - Assessments',
    icon: Icons.key_outlined,
    summary: 'Versioned answer keys. A published key is immutable; a correction creates the next version with a recorded reason, and re-scoring supersedes results rather than overwriting them.',
    capabilities: <String>[
      'Key entry and validation against the assessment question count',
      'Publication, after which the version can never be edited',
      'Correction as a new version with a mandatory change reason',
      'Full version history, so an old score stays explainable',
    ],
  );
}
