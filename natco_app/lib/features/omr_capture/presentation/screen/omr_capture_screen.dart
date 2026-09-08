/// Capture OMR screen.
///
/// Implemented in Phase 5 - OMR Capture; see docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/feature_preview_screen.dart';

final class OmrCaptureScreen extends StatelessWidget {
  const OmrCaptureScreen({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePreviewScreen(
    title: 'Capture OMR',
    phase: 'Phase 5 - OMR Capture',
    icon: Icons.photo_camera_outlined,
    summary: 'Camera and gallery capture with a quality gate before any processing. The photograph is written to durable storage first, so a crash cannot destroy the evidence.',
    capabilities: <String>[
      'Camera preview with corner guidance and automatic sheet detection',
      'Gallery import for sheets photographed earlier',
      'Quality checks for blur, brightness, contrast, shadow, resolution and coverage',
      'A specific message per failure, with Retake, Use Anyway (permission-gated) and Cancel',
      'Manual OMR ID entry when the printed ID cannot be read',
    ],
  );
}
