/// An OMR submission's full lifecycle (docs/07-omr-pipeline.md §4, "State
/// machine (§47)").
///
/// This phase (5, capture) only ever writes `captured`, `qualityChecked` and
/// `qualityFailed` — a submission sits at `qualityChecked` once analysis
/// passes, waiting for Phase 6's marker detection and bubble sampling to
/// pick it up. The remaining values are named here because the full pipeline
/// names them, but nothing in this phase produces them; see
/// `OmrStateMachine`'s doc comment for exactly which transitions this phase
/// implements.
library;

enum OmrProcessingStatus {
  captured('CAPTURED'),
  qualityChecked('QUALITY_CHECKED'),
  qualityFailed('QUALITY_FAILED'),
  processing('PROCESSING'),
  processingFailed('PROCESSING_FAILED'),
  processed('PROCESSED'),
  needsValidation('NEEDS_VALIDATION'),
  validated('VALIDATED'),
  readyForScoring('READY_FOR_SCORING'),
  scored('SCORED'),
  syncPending('SYNC_PENDING'),
  synced('SYNCED'),
  duplicateBlocked('DUPLICATE_BLOCKED'),
  unreadableEvidenceMissing('UNREADABLE_EVIDENCE_MISSING');

  const OmrProcessingStatus(this.wireName);

  final String wireName;

  static final Map<String, OmrProcessingStatus> _byWireName =
      <String, OmrProcessingStatus>{
        for (final OmrProcessingStatus status in OmrProcessingStatus.values)
          status.wireName: status,
      };

  static OmrProcessingStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];
}
