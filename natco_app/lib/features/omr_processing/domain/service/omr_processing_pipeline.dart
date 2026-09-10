/// The OMR engine itself: Steps 3-11 of docs/07-omr-pipeline.md, chained.
///
/// Deliberately a plain, side-effect-free function of its inputs — no
/// repository, no `Ref`, nothing that only exists inside the app process —
/// so the exact same call can run inside `Isolate.run` (`OmrPipelineRunner`)
/// and inside the golden-dataset harness (`tool/omr_eval.dart`), and so a
/// unit test can call it directly with no fakes.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/marker_detection_result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_processing_outcome.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/entity/question_detection_result.dart';
import 'package:natco_app/features/omr_processing/domain/service/answer_classifier.dart';
import 'package:natco_app/features/omr_processing/domain/service/bubble_sampler.dart';
import 'package:natco_app/features/omr_processing/domain/service/marker_detector.dart';
import 'package:natco_app/features/omr_processing/domain/service/sheet_rectifier.dart';

/// Long edge the original captured image is downscaled to before detection —
/// the same fixed working resolution `ImageQualityAnalyzer` uses for its own
/// pass over the same photo (docs/07-omr-pipeline.md Step 1), kept as a
/// separate constant here rather than a shared import because the two call
/// sites are free to tune their own working resolution independently.
const int kOmrProcessingWorkingLongEdge = 1600;

final class OmrProcessingPipeline {
  const OmrProcessingPipeline({
    this.markerDetector = const MarkerDetector(),
    this.rectifier = const SheetRectifier(),
    this.sampler = const BubbleSampler(),
    this.classifier = const AnswerClassifier(),
  });

  final MarkerDetector markerDetector;
  final SheetRectifier rectifier;
  final BubbleSampler sampler;
  final AnswerClassifier classifier;

  /// Runs the full engine over [originalImageBytes]. A [Failure] here means
  /// the sheet could not be processed at all (an undecodable file, or fewer
  /// than four markers found) — the caller maps that to
  /// `PROCESSING_FAILED`, per `OmrStateMachine`. A successful [Result]
  /// means every question from 1 to [questionCount] was classified, and
  /// [OmrProcessingOutcome.needsValidation] carries Step 11's decision.
  Result<OmrProcessingOutcome> process(
    Uint8List originalImageBytes, {
    required OmrTemplate template,
    required int questionCount,
    required ScannerThresholds thresholds,
    required double imageQualityScore,
    bool qualityWasOverridden = false,
  }) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(originalImageBytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      return err(
        const ValidationFailure(
          userMessage: 'That file could not be read as an image.',
        ),
      );
    }

    final img.Image working = _downscale(
      decoded,
      kOmrProcessingWorkingLongEdge,
    );

    final Result<MarkerDetectionResult> markerResult = markerDetector.detect(
      working,
    );
    if (markerResult.isFailure) {
      return err(markerResult.failureOrNull!);
    }

    final img.Image rectified = rectifier.rectify(
      working,
      detection: markerResult.valueOrNull!,
      template: template,
    );

    final List<QuestionDetectionResult> results = <QuestionDetectionResult>[
      for (int question = 1; question <= questionCount; question++)
        classifier.classify(
          questionNumber: question,
          optionScores: sampler.sampleQuestion(
            rectified,
            template: template,
            questionNumber: question,
            thresholds: thresholds.bubbles,
          ),
          optionLabels: template.optionLabels,
          thresholds: thresholds.bubbles,
          confidenceWeights: thresholds.confidence,
          imageQualityScore: imageQualityScore,
        ),
    ];

    final bool anyRequiresValidation = results.any(
      (QuestionDetectionResult r) => r.machineStatus.requiresValidation,
    );
    final bool anyMediumNeedsValidation =
        thresholds.requireValidationForMediumConfidence &&
        results.any(
          (QuestionDetectionResult r) =>
              r.machineStatus == DetectionStatus.mediumConfidence,
        );

    return ok(
      OmrProcessingOutcome(
        questionResults: results,
        needsValidation:
            qualityWasOverridden ||
            anyRequiresValidation ||
            anyMediumNeedsValidation,
      ),
    );
  }

  img.Image _downscale(img.Image image, int longEdge) {
    final int longestSide = image.width > image.height
        ? image.width
        : image.height;
    if (longestSide <= longEdge) {
      return image;
    }
    return image.width >= image.height
        ? img.copyResize(image, width: longEdge)
        : img.copyResize(image, height: longEdge);
  }
}
