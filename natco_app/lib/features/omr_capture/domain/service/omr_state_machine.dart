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
/// The doc's own state diagram carries hedges the remaining transitions
/// don't have yet ("terminal unless overridden or retaken", two "also
/// terminal" states with no drawn source edge) — the source design is not
/// itself fully pinned down beyond this phase's own three edges. Phase 6
/// onward extend this table with `PROCESSING` and beyond as those pipeline
/// stages are actually built, rather than this phase guessing their exact
/// preconditions.
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
    },
    OmrProcessingStatus.qualityFailed: <OmrProcessingStatus>{
      OmrProcessingStatus.qualityChecked,
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
