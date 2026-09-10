/// Per-question machine detection outcome (docs/02-data-model.md `OmrAnswer.
/// machineStatus`).
library;

enum DetectionStatus {
  highConfidence,
  mediumConfidence,
  lowConfidence,
  blank,
  multipleMark,

  /// The bubble region could not be sampled at all (occlusion, a tear, a
  /// missing region) — produced upstream of classification, per
  /// docs/07-omr-pipeline.md Step 9. Not yet producible by this phase's
  /// classifier, which always has a rectified region to sample; occlusion
  /// detection is a later refinement, not a capability this enum value
  /// pretends already exists.
  unreadable;

  String get wireName => switch (this) {
    DetectionStatus.highConfidence => 'HIGH_CONFIDENCE',
    DetectionStatus.mediumConfidence => 'MEDIUM_CONFIDENCE',
    DetectionStatus.lowConfidence => 'LOW_CONFIDENCE',
    DetectionStatus.blank => 'BLANK',
    DetectionStatus.multipleMark => 'MULTIPLE_MARK',
    DetectionStatus.unreadable => 'UNREADABLE',
  };

  static DetectionStatus? tryFromWireName(String wireName) => switch (wireName) {
    'HIGH_CONFIDENCE' => DetectionStatus.highConfidence,
    'MEDIUM_CONFIDENCE' => DetectionStatus.mediumConfidence,
    'LOW_CONFIDENCE' => DetectionStatus.lowConfidence,
    'BLANK' => DetectionStatus.blank,
    'MULTIPLE_MARK' => DetectionStatus.multipleMark,
    'UNREADABLE' => DetectionStatus.unreadable,
    _ => null,
  };

  /// Whether a question in this status forces the submission to
  /// `NEEDS_VALIDATION` (docs/07-omr-pipeline.md Step 11).
  bool get requiresValidation =>
      this == DetectionStatus.lowConfidence ||
      this == DetectionStatus.multipleMark ||
      this == DetectionStatus.unreadable;
}
