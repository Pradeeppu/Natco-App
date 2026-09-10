/// Runs the OMR engine off the UI thread.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_processing_outcome.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processing_pipeline.dart';

/// An interface (rather than calling `Isolate.run` directly from
/// `OmrProcessingService`) for the same reason `ImagePickerService` is one:
/// tests can substitute a same-isolate runner that calls
/// `OmrProcessingPipeline` directly — real isolate spawning inside a
/// widget test's `tester.runAsync` zone has real, but not `flutter test`
/// -reliable, wall-clock timing, whereas `OmrProcessingService`'s own
/// integration with the repositories is what such a test actually needs to
/// prove.
abstract interface class OmrPipelineRunner {
  Future<Result<OmrProcessingOutcome>> run(
    Uint8List originalImageBytes, {
    required OmrTemplate template,
    required int questionCount,
    required ScannerThresholds thresholds,
    required double imageQualityScore,
    bool qualityWasOverridden = false,
  });
}

/// Runs `OmrProcessingPipeline` in a worker isolate, so the pixel-level work
/// in Steps 3-10 never blocks the UI thread (docs/07-omr-pipeline.md:
/// "Steps 1-10 run in a worker isolate. The UI thread only ever sees a
/// progress stream and a final result object").
///
/// Deliberately without that progress stream: a determinate progress bar is
/// only honest once the calibration harness has measured real per-stage
/// timings against the performance budget it names (docs/07-omr-
/// pipeline.md §6), and nothing has run that harness yet. A single opaque
/// isolate call — the UI shows a busy indicator for its duration — matches
/// what this phase can actually claim; a fabricated progress percentage
/// would not.
final class IsolateOmrPipelineRunner implements OmrPipelineRunner {
  const IsolateOmrPipelineRunner();

  @override
  Future<Result<OmrProcessingOutcome>> run(
    Uint8List originalImageBytes, {
    required OmrTemplate template,
    required int questionCount,
    required ScannerThresholds thresholds,
    required double imageQualityScore,
    bool qualityWasOverridden = false,
  }) => Isolate.run(
    () => const OmrProcessingPipeline().process(
      originalImageBytes,
      template: template,
      questionCount: questionCount,
      thresholds: thresholds,
      imageQualityScore: imageQualityScore,
      qualityWasOverridden: qualityWasOverridden,
    ),
  );
}
