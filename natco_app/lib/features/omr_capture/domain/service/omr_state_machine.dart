/// Validates `OmrProcessingStatus` transitions (docs/07-omr-pipeline.md §4).
///
/// "Transitions go through a single `OmrStateMachine.transition(from, to)`
/// that returns a `Result`. An illegal transition is rejected, logged, and
/// never applied — the entity keeps its previous state rather than entering
/// an invented one."
///
/// Only the transitions Phase 5 (capture) can reach are implemented here:
///
/// * `CAPTURED → QUALITY_CHECKED` — quality analysis ran (docs/07-omr-
///   pipeline.md Step 2), whatever its verdict.
/// * `QUALITY_CHECKED → QUALITY_FAILED` — the verdict was `FAIL`.
/// * `QUALITY_FAILED → QUALITY_CHECKED` — a Supervisor or Super Admin
///   overrode the gate ("Use Anyway"), which `overrideQualityGate` alone may
///   do (docs/04-security-model.md).
///
/// Phase 6 (the detection engine) adds the transitions that carry a
/// submission from a passed quality gate through to a scoring-readiness
/// decision:
///
/// * `QUALITY_CHECKED → PROCESSING` — the engine picked the sheet up.
/// * `PROCESSING → PROCESSING_FAILED` — markers could not be found (fewer
///   than four detected) or the rectified image could not be aligned to the
///   template (docs/07-omr-pipeline.md Step 3).
/// * `PROCESSING_FAILED → PROCESSING` — a retry (docs/07-omr-pipeline.md
///   §4's own diagram draws this as the one edge out of a processing
///   failure).
/// * `PROCESSING → PROCESSED` — every question was sampled and classified.
/// * `PROCESSED → NEEDS_VALIDATION` / `PROCESSED → READY_FOR_SCORING` — the
///   Step 11 validation decision, computed from the classified answers'
///   statuses (`DetectionStatus.requiresValidation`) rather than guessed.
///
/// `VALIDATED`, `SCORED`, `SYNC_PENDING`, `SYNCED`, `DUPLICATE_BLOCKED` and
/// `UNREADABLE_EVIDENCE_MISSING` remain out of this table — they belong to
/// the review queue (Phase 7), scoring (Phase 8) and sync (Phase 9) this
/// phase does not build, the same reasoning Phase 5's version of this class
/// gave for leaving Phase 6's own edges out until Phase 6 existed to define
/// their real preconditions.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';

final class OmrStateMachine {
  const OmrStateMachine();

  static const Map<OmrProcessingStatus, Set<OmrProcessingStatus>>
  _legalTransitions = <OmrProcessingStatus, Set<OmrProcessingStatus>>{
    OmrProcessingStatus.captured: <OmrProcessingStatus>{
      OmrProcessingStatus.qualityChecked,
    },
    OmrProcessingStatus.qualityChecked: <OmrProcessingStatus>{
      OmrProcessingStatus.qualityFailed,
      OmrProcessingStatus.processing,
    },
    OmrProcessingStatus.qualityFailed: <OmrProcessingStatus>{
      OmrProcessingStatus.qualityChecked,
    },
    OmrProcessingStatus.processing: <OmrProcessingStatus>{
      OmrProcessingStatus.processingFailed,
      OmrProcessingStatus.processed,
    },
    OmrProcessingStatus.processingFailed: <OmrProcessingStatus>{
      OmrProcessingStatus.processing,
    },
    OmrProcessingStatus.processed: <OmrProcessingStatus>{
      OmrProcessingStatus.needsValidation,
      OmrProcessingStatus.readyForScoring,
    },
  };

  bool canTransition(OmrProcessingStatus from, OmrProcessingStatus to) =>
      _legalTransitions[from]?.contains(to) ?? false;

  Result<OmrProcessingStatus> transition(
    OmrProcessingStatus from,
    OmrProcessingStatus to,
  ) {
    if (!canTransition(from, to)) {
      return err(
        IllegalStateTransitionFailure(
          entityType: 'omr_submission',
          from: from.wireName,
          to: to.wireName,
        ),
      );
    }
    return ok(to);
  }
}
