/// An assessment's lifecycle (docs/02-data-model.md section 4).
///
/// Transitions are linear and forward-only — `DRAFT → PUBLISHED → ACTIVE →
/// SCORING_LOCKED → CLOSED → ARCHIVED` — the same posture as
/// `AssessmentSession`'s state machine (docs/02-data-model.md section 5): an
/// illegal transition is a real, expected condition (a stale screen retrying
/// a step that already happened) and is rejected rather than silently
/// applied.
library;

enum AssessmentStatus {
  draft('DRAFT', 'Draft'),
  published('PUBLISHED', 'Published'),
  active('ACTIVE', 'Active'),
  scoringLocked('SCORING_LOCKED', 'Scoring locked'),
  closed('CLOSED', 'Closed'),
  archived('ARCHIVED', 'Archived');

  const AssessmentStatus(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, AssessmentStatus> _byWireName =
      <String, AssessmentStatus>{
        for (final AssessmentStatus status in AssessmentStatus.values)
          status.wireName: status,
      };

  static AssessmentStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  /// Whether moving from this status directly to [next] is a legal step in
  /// the linear lifecycle above. Skipping a step (`DRAFT` straight to
  /// `ACTIVE`) or moving backward is never legal.
  bool canTransitionTo(AssessmentStatus next) =>
      next.index == index + 1;
}
