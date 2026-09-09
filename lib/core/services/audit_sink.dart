/// Audit trail.
///
/// Requirement section 26 lists the fields; Critical Rules 5 and 6 are the
/// reason the trail exists at all. An audit entry is written by the same code
/// path that performs the action, so an action cannot succeed unrecorded.
///
/// Entries are append-only. `firebase/firestore.rules` denies update and
/// delete on `audit_logs` to every client, including Super Admin.
library;

/// Auditable actions. Names are stable — reports and queries depend on them.
enum AuditAction {
  loginSucceeded('LOGIN_SUCCEEDED'),
  loginFailed('LOGIN_FAILED'),
  logout('LOGOUT'),
  omrCaptured('OMR_CAPTURED'),
  omrScanned('OMR_SCANNED'),
  omrValidated('OMR_VALIDATED'),
  omrQualityOverridden('OMR_QUALITY_OVERRIDDEN'),
  omrDuplicateResolved('OMR_DUPLICATE_RESOLVED'),
  scoreGenerated('SCORE_GENERATED'),
  scoreCorrected('SCORE_CORRECTED'),
  answerKeyPublished('ANSWER_KEY_PUBLISHED'),
  answerKeyUpdated('ANSWER_KEY_UPDATED'),
  answerKeyCorrectionStarted('ANSWER_KEY_CORRECTION_STARTED'),
  assessmentCreated('ASSESSMENT_CREATED'),
  assessmentUpdated('ASSESSMENT_UPDATED'),
  assessmentStatusChanged('ASSESSMENT_STATUS_CHANGED'),
  assessmentAssigned('ASSESSMENT_ASSIGNED'),
  assessmentUnassigned('ASSESSMENT_UNASSIGNED'),
  sessionCreated('SESSION_CREATED'),
  sessionStatusChanged('SESSION_STATUS_CHANGED'),
  sessionAbandoned('SESSION_ABANDONED'),
  sessionAttendanceMarked('SESSION_ATTENDANCE_MARKED'),
  studentCreated('STUDENT_CREATED'),
  studentUpdated('STUDENT_UPDATED'),
  studentImportCompleted('STUDENT_IMPORT_COMPLETED'),
  stateCreated('STATE_CREATED'),
  stateUpdated('STATE_UPDATED'),
  districtCreated('DISTRICT_CREATED'),
  districtUpdated('DISTRICT_UPDATED'),
  clusterCreated('CLUSTER_CREATED'),
  clusterUpdated('CLUSTER_UPDATED'),
  schoolCreated('SCHOOL_CREATED'),
  schoolUpdated('SCHOOL_UPDATED'),
  assessmentStarted('ASSESSMENT_STARTED'),
  assessmentCompleted('ASSESSMENT_COMPLETED'),
  syncConflictResolved('SYNC_CONFLICT_RESOLVED'),
  userCreated('USER_CREATED'),
  userUpdated('USER_UPDATED'),
  userRoleChanged('USER_ROLE_CHANGED'),
  userDeactivated('USER_DEACTIVATED'),
  userReactivated('USER_REACTIVATED'),
  scannerThresholdsChanged('SCANNER_THRESHOLDS_CHANGED'),
  reportExported('REPORT_EXPORTED'),
  permissionDenied('PERMISSION_DENIED');

  const AuditAction(this.wireName);

  /// Persisted form. Kept separate from the Dart name so renaming the enum
  /// member never rewrites history.
  final String wireName;
}

/// One audit record.
final class AuditEvent {
  const AuditEvent({
    required this.auditId,
    required this.userId,
    required this.role,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.timestamp,
    required this.deviceId,
    required this.appVersion,
    this.oldValue,
    this.newValue,
  });

  final String auditId;
  final String userId;

  /// Wire name of the actor's role at the time of the action. Stored rather
  /// than looked up later, because the actor's role may change afterwards and
  /// the record must describe what was true when it happened.
  final String role;

  final AuditAction action;
  final String entityType;
  final String entityId;
  final DateTime timestamp;
  final String deviceId;
  final String appVersion;

  /// Redacted before-and-after values: field names and non-personal values
  /// only (requirement section 35).
  final Map<String, Object?>? oldValue;
  final Map<String, Object?>? newValue;

  Map<String, Object?> toJson() => <String, Object?>{
    'auditId': auditId,
    'userId': userId,
    'role': role,
    'action': action.wireName,
    'entityType': entityType,
    'entityId': entityId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'appVersion': appVersion,
    if (oldValue != null) 'oldValue': oldValue,
    if (newValue != null) 'newValue': newValue,
  };
}

/// Destination for audit events.
///
/// Writes are queued locally first, exactly like any other field write, so an
/// action performed offline is still audited (docs/06-offline-sync-strategy.md).
abstract interface class AuditSink {
  Future<void> record(AuditEvent event);
}

/// Collects events in memory. Used by tests and demo mode.
final class InMemoryAuditSink implements AuditSink {
  final List<AuditEvent> _events = <AuditEvent>[];

  List<AuditEvent> get events => List<AuditEvent>.unmodifiable(_events);

  @override
  Future<void> record(AuditEvent event) async => _events.add(event);

  void clear() => _events.clear();
}
