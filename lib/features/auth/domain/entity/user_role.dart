/// The six user roles and their permission sets.
///
/// The monitoring role is **Supervisor**. The word "Coordinator" is not used   allow-coordinator-reference
/// anywhere in this product (requirement section 1).
///
/// One role per user. A union-of-permissions multi-role model was rejected
/// because it makes "why can this person see that school?" unanswerable, and
/// that question has to stay answerable (docs/04-security-model.md).
library;

import 'package:natco_app/features/auth/domain/entity/permission.dart';

enum UserRole {
  superAdmin('SUPER_ADMIN', 'Super Admin'),

  /// Called "NATCO Admin" on screen. The wire name stays `ASSESSMENT_ADMIN`
  /// because it is written into custom claims, stored user documents and
  /// `firebase/firestore.rules`; renaming it would invalidate every existing
  /// session and role document to change a label.
  assessmentAdmin('ASSESSMENT_ADMIN', 'NATCO Admin'),
  supervisor('SUPERVISOR', 'Supervisor'),
  pstTeacher('PST_TEACHER', 'PST Teacher'),
  scannerOperator('SCANNER_OPERATOR', 'Scanner Operator'),
  viewer('VIEWER', 'Viewer');

  const UserRole(this.wireName, this.displayName);

  /// Persisted/transmitted name, also used in Auth custom claims.
  final String wireName;

  /// Label shown in the UI.
  final String displayName;

  static final Map<String, UserRole> _byWireName = <String, UserRole>{
    for (final UserRole role in UserRole.values) role.wireName: role,
  };

  /// Resolves a role from its wire name.
  ///
  /// Returns `null` for an unknown value. The caller must then refuse the
  /// session rather than guess: an unrecognised role granted the *least*
  /// privilege would still be a user with an undefined identity, and granting
  /// anything at all to a role this build does not understand is worse.
  static UserRole? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  /// The permissions this role holds.
  ///
  /// Backed by a compile-time constant map, so the matrix is data rather than
  /// a chain of conditionals and can be asserted wholesale in tests.
  Set<Permission> get permissions => kRolePermissions[this]!;

  bool can(Permission permission) => permissions.contains(permission);

  /// The roles a holder of this role may create or edit.
  ///
  /// [Permission.manageUsers] answers "may this person touch user accounts at
  /// all". It does not answer "which accounts", and on its own it would let a
  /// Supervisor mint a Super Admin — a one-tap privilege escalation that no
  /// scope check would catch, because a Super Admin has no scope to be outside
  /// of. This is the second half of that decision, and
  /// [AccessScope] is the third: a Supervisor may add PST Teachers, and only
  /// inside their own clusters.
  ///
  /// Mirrored by `isAssignableRole()` in `firebase/firestore.rules`. A role
  /// absent from every set here can be held but never created from the app.
  Set<UserRole> get assignableRoles => kAssignableRoles[this] ?? const <UserRole>{};

  bool canAssign(UserRole role) => assignableRoles.contains(role);
}

/// Which roles each role may hand out.
///
/// Deliberately not derived from the permission matrix: "may manage users" and
/// "may create *this* user" are different questions, and conflating them is
/// exactly the bug this map exists to prevent.
const Map<UserRole, Set<UserRole>> kAssignableRoles = <UserRole, Set<UserRole>>{
  UserRole.superAdmin: <UserRole>{
    UserRole.superAdmin,
    UserRole.assessmentAdmin,
    UserRole.supervisor,
    UserRole.pstTeacher,
    UserRole.scannerOperator,
    UserRole.viewer,
  },

  // A Supervisor adds PST Teachers, and nothing else. Not a Scanner Operator
  // (who may capture without a teacher's scope narrowing), not another
  // Supervisor (which would let two Supervisors widen each other's reach), and
  // certainly not an admin.
  UserRole.supervisor: <UserRole>{UserRole.pstTeacher},
};

/// The role-to-permission matrix.
///
/// Mirrored in `firebase/firestore.rules` and documented as a table in
/// docs/04-security-model.md. Read that table for the reasoning behind the
/// non-obvious entries; the important ones are noted inline here.
const Map<UserRole, Set<Permission>> kRolePermissions =
    <UserRole, Set<Permission>>{
      // Super Admin holds every permission. Written out rather than derived
      // from `Permission.values` so that adding a permission is a deliberate
      // decision about who gets it, not an automatic grant.
      UserRole.superAdmin: <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.manageStates,
        Permission.manageDistricts,
        Permission.manageClusters,
        Permission.manageSchools,
        Permission.viewStudents,
        Permission.manageStudents,
        Permission.importStudents,
        Permission.viewUsers,
        Permission.manageUsers,
        Permission.manageSystemConfig,
        Permission.viewAssessments,
        Permission.manageAssessments,
        Permission.manageQuestions,
        Permission.manageAnswerKey,
        Permission.manageAssessmentStatus,
        Permission.manageAssignments,
        Permission.conductAssessment,
        Permission.captureOmr,
        Permission.processOmr,
        Permission.reviewScanQuality,
        Permission.overrideQualityGate,
        Permission.viewOmrImage,
        Permission.resolveDuplicateOmr,
        Permission.validateOmr,
        Permission.reviewExceptions,
        Permission.viewResults,
        Permission.viewOwnSubmissions,
        Permission.correctScore,
        Permission.viewAnalytics,
        Permission.viewQuestionAnalytics,
        Permission.exportReports,
        Permission.syncSubmissions,
        Permission.resolveSyncConflict,
        Permission.calibrateScanner,
        Permission.viewAuditLog,
      },

      UserRole.assessmentAdmin: <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.viewStudents,
        Permission.viewAssessments,
        Permission.manageAssessments,
        Permission.manageQuestions,
        Permission.manageAnswerKey,
        Permission.manageAssessmentStatus,
        Permission.manageAssignments,
        Permission.viewResults,
        Permission.viewAnalytics,
        Permission.viewQuestionAnalytics,
        // Granted beyond the literal wording of requirement section 9: this
        // role is defined by reading assessment analytics, and section 32
        // lists assessment summary and question analysis as report types.
        // Exports are reads, and every export is audited.
        Permission.exportReports,
      },

      UserRole.supervisor: <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.viewStudents,
        Permission.viewAssessments,
        // A Supervisor onboards the PST Teachers in their own clusters, so
        // staffing a new school does not queue behind a Super Admin. The
        // permission is bounded twice over: `assignableRoles` limits it to
        // PST Teacher, and the Supervisor's own `AccessScope` limits it to
        // their clusters.
        Permission.viewUsers,
        Permission.manageUsers,
        Permission.reviewScanQuality,
        // Only Supervisors and Super Admins may waive the image-quality gate.
        // The person under time pressure in the classroom is exactly the wrong
        // person to be able to admit unreadable evidence, and Critical Rule 15
        // requires the original to stay usable for audit.
        Permission.overrideQualityGate,
        Permission.viewOmrImage,
        Permission.resolveDuplicateOmr,
        Permission.validateOmr,
        Permission.reviewExceptions,
        Permission.viewResults,
        Permission.viewAnalytics,
        Permission.viewQuestionAnalytics,
        Permission.exportReports,
        Permission.syncSubmissions,
        Permission.resolveSyncConflict,
      },

      UserRole.pstTeacher: <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.viewStudents,
        // The teacher enters their own class. Registering a child at the
        // desk is the same act as teaching them, and routing it through an
        // admin is what produces the free-typed names requirement §10 exists
        // to prevent. Bounded by the teacher's grade-section scope, so this
        // reaches 5-A and not 5-B.
        //
        // `importStudents` is deliberately *not* granted: the matrix already
        // separates single entry from bulk load, and a mis-mapped CSV column
        // is a whole-class error rather than a one-row one.
        Permission.manageStudents,
        Permission.viewAssessments,
        Permission.conductAssessment,
        Permission.captureOmr,
        Permission.processOmr,
        Permission.reviewScanQuality,
        Permission.viewOmrImage,
        Permission.viewResults,
        Permission.viewOwnSubmissions,
        // Report cards for the teacher's own students. Every export is
        // audited and no student name reaches a filename (§32, Critical
        // Rule 11).
        Permission.exportReports,
        Permission.syncSubmissions,
      },

      UserRole.scannerOperator: <Permission>{
        Permission.viewDashboard,
        // Holds viewAssessments without an Assessments destination: the
        // operator must pick the assessment being scanned, and that choice
        // happens inside the capture flow (docs/05-navigation-map.md).
        Permission.viewAssessments,
        Permission.captureOmr,
        Permission.processOmr,
        Permission.reviewScanQuality,
        Permission.viewOmrImage,
        Permission.viewOwnSubmissions,
        Permission.syncSubmissions,
      },

      UserRole.viewer: <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.viewStudents,
        Permission.viewAssessments,
        Permission.viewResults,
        Permission.viewAnalytics,
        Permission.viewQuestionAnalytics,
        Permission.exportReports,
      },
    };
