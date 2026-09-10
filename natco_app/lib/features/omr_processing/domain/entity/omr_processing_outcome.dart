/// The result of running the whole engine (docs/07-omr-pipeline.md
/// Steps 3-11) over one captured sheet.
library;

import 'package:natco_app/features/omr_processing/domain/entity/question_detection_result.dart';

final class OmrProcessingOutcome {
  const OmrProcessingOutcome({
    required this.questionResults,
    required this.needsValidation,
  });

  final List<QuestionDetectionResult> questionResults;

  /// Step 11's validation decision: any question needing a human, or the
  /// quality gate having been overridden, routes the whole sheet to
  /// `NEEDS_VALIDATION` rather than straight to `READY_FOR_SCORING`
  /// (docs/07-omr-pipeline.md Step 11).
  final bool needsValidation;
}
