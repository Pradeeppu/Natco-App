/// Permissions and the role-to-permission matrix.
///
/// This file is the single source of truth for "what may this role do".
/// `firebase/firestore.rules` mirrors it, and `roles/{roleId}` holds a
/// read-only copy for the rules to consult. When the matrix changes here, both
/// mirrors change with it — a drift between them is a security bug, and the
/// test suite asserts the counts to make drift visible.
///
/// Permissions answer *what*. [AccessScope] answers *which schools*. Both are
/// checked (docs/04-security-model.md).
library;

/// A single authorised action.
enum Permission {
  viewDashboard('viewDashboard'),

  // ---- Geographic master data
  viewSchools('viewSchools'),
  manageStates('manageStates'),
  manageDistricts('manageDistricts'),
  manageClusters('manageClusters'),
  manageSchools('manageSchools'),

  // ---- Students
  viewStudents('viewStudents'),
  manageStudents('manageStudents'),
  importStudents('importStudents'),

  // ---- Users and configuration
  viewUsers('viewUsers'),
  manageUsers('manageUsers'),
  manageSystemConfig('manageSystemConfig'),

  // ---- Assessments
  viewAssessments('viewAssessments'),
  manageAssessments('manageAssessments'),
  manageQuestions('manageQuestions'),
  manageAnswerKey('manageAnswerKey'),
  manageAssessmentStatus('manageAssessmentStatus'),
  manageAssignments('manageAssignments'),

  // ---- Sessions
  conductAssessment('conductAssessment'),

  // ---- OMR
  captureOmr('captureOmr'),
  processOmr('processOmr'),
  reviewScanQuality('reviewScanQuality'),
  overrideQualityGate('overrideQualityGate'),
  viewOmrImage('viewOmrImage'),
  resolveDuplicateOmr('resolveDuplicateOmr'),

  // ---- Validation
  validateOmr('validateOmr'),
  reviewExceptions('reviewExceptions'),

  // ---- Results
  viewResults('viewResults'),
  viewOwnSubmissions('viewOwnSubmissions'),
  correctScore('correctScore'),

  // ---- Analytics and reports
  viewAnalytics('viewAnalytics'),
  viewQuestionAnalytics('viewQuestionAnalytics'),
  exportReports('exportReports'),

  // ---- Sync
  syncSubmissions('syncSubmissions'),
  resolveSyncConflict('resolveSyncConflict'),

  // ---- Scanner calibration
  calibrateScanner('calibrateScanner'),

  // ---- Audit
  viewAuditLog('viewAuditLog');

  const Permission(this.wireName);

  /// Persisted/transmitted name. Kept separate from the Dart identifier so a
  /// refactor here cannot invalidate stored role documents or security rules.
  final String wireName;

  static final Map<String, Permission> _byWireName = <String, Permission>{
    for (final Permission p in Permission.values) p.wireName: p,
  };

  /// Looks up a permission by wire name, or `null` if unknown.
  ///
  /// Unknown names resolve to `null` rather than throwing: a client running an
  /// older build must tolerate a permission the server added later, and it
  /// must do so by *not granting* it.
  static Permission? tryFromWireName(String name) => _byWireName[name];
}

/// A short human-readable phrase describing an action, used to build
/// user-facing messages such as "You do not have permission to validate OMR
/// sheets."
extension PermissionDescription on Permission {
  String get actionPhrase => switch (this) {
    Permission.viewDashboard => 'view the dashboard',
    Permission.viewSchools => 'view schools',
    Permission.manageStates => 'manage states',
    Permission.manageDistricts => 'manage districts',
    Permission.manageClusters => 'manage clusters',
    Permission.manageSchools => 'manage schools',
    Permission.viewStudents => 'view students',
    Permission.manageStudents => 'manage students',
    Permission.importStudents => 'import students',
    Permission.viewUsers => 'view users',
    Permission.manageUsers => 'manage users',
    Permission.manageSystemConfig => 'change system configuration',
    Permission.viewAssessments => 'view assessments',
    Permission.manageAssessments => 'manage assessments',
    Permission.manageQuestions => 'configure questions',
    Permission.manageAnswerKey => 'manage answer keys',
    Permission.manageAssessmentStatus => 'change assessment status',
    Permission.manageAssignments => 'assign assessments',
    Permission.conductAssessment => 'conduct assessments',
    Permission.captureOmr => 'capture OMR sheets',
    Permission.processOmr => 'process OMR sheets',
    Permission.reviewScanQuality => 'review scan quality',
    Permission.overrideQualityGate => 'accept a low-quality scan',
    Permission.viewOmrImage => 'view OMR images',
    Permission.resolveDuplicateOmr => 'resolve duplicate OMR sheets',
    Permission.validateOmr => 'validate OMR sheets',
    Permission.reviewExceptions => 'review exceptions',
    Permission.viewResults => 'view results',
    Permission.viewOwnSubmissions => 'view your own submissions',
    Permission.correctScore => 'correct scores',
    Permission.viewAnalytics => 'view analytics',
    Permission.viewQuestionAnalytics => 'view question analytics',
    Permission.exportReports => 'export reports',
    Permission.syncSubmissions => 'synchronise submissions',
    Permission.resolveSyncConflict => 'resolve sync conflicts',
    Permission.calibrateScanner => 'calibrate the scanner',
    Permission.viewAuditLog => 'view the audit log',
  };
}
