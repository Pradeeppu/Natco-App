/// An assessment session's lifecycle (docs/02-data-model.md section 5).
///
/// Linear and forward-only, the same posture as `AssessmentStatus` and
/// `AssignmentStatus`: "Transitions are validated by a state machine;
/// illegal transitions are rejected and logged" (requirement section 47). A
/// retried or resumed screen requesting a step that already happened is a
/// real, expected condition, not a bug to paper over.
///
/// Phase 4 (this phase) only ever writes `draft`, `started`, `inProgress` and
/// `completed` — a session is created directly at `started` (there is
/// nothing to persist about a session that only exists as an unfilled form
/// on screen) and a teacher ends it at `completed`. `syncPending`, `synced`
/// and `closed` are reserved for Phase 9, once a sync engine exists to move a
/// session through them; the enum carries all seven now so that phase does
/// not have to touch this file to add a value in the middle of the sequence.
library;

enum SessionStatus {
  draft('DRAFT', 'Draft'),
  started('STARTED', 'Started'),
  inProgress('IN_PROGRESS', 'In progress'),
  completed('COMPLETED', 'Completed'),
  syncPending('SYNC_PENDING', 'Sync pending'),
  synced('SYNCED', 'Synced'),
  closed('CLOSED', 'Closed');

  const SessionStatus(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, SessionStatus> _byWireName = <String, SessionStatus>{
    for (final SessionStatus status in SessionStatus.values) status.wireName: status,
  };

  static SessionStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  bool canTransitionTo(SessionStatus next) => next.index == index + 1;
}
