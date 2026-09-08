/// Tests for the role-to-permission matrix.
///
/// The matrix is a security boundary, so these tests assert it exhaustively
/// rather than spot-checking: every role's exact permission set is pinned, so
/// that granting a permission is always a visible, deliberate diff.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

void main() {
  group('UserRole', () {
    test('has exactly the six roles the requirements define', () {
      expect(UserRole.values, hasLength(6));
      expect(UserRole.values.map((UserRole r) => r.wireName).toSet(), <String>{
        'SUPER_ADMIN',
        'ASSESSMENT_ADMIN',
        'SUPERVISOR',
        'PST_TEACHER',
        'SCANNER_OPERATOR',
        'VIEWER',
      });
    });

    test('names the monitoring role Supervisor, never Coordinator', () {
      // allow-coordinator-reference
      const UserRole supervisor = UserRole.supervisor;
      expect(supervisor.displayName, 'Supervisor');
      expect(supervisor.wireName, 'SUPERVISOR');
      for (final UserRole role in UserRole.values) {
        expect(
          role.displayName.toLowerCase(),
          isNot(contains('coordinator')),
        ); // allow-coordinator-reference
        expect(
          role.wireName.toLowerCase(),
          isNot(contains('coordinator')),
        ); // allow-coordinator-reference
      }
    });

    test('resolves from wire name and returns null for anything unknown', () {
      expect(UserRole.tryFromWireName('SUPERVISOR'), UserRole.supervisor);
      expect(
        UserRole.tryFromWireName('COORDINATOR'),
        isNull,
      ); // allow-coordinator-reference
      expect(UserRole.tryFromWireName('supervisor'), isNull);
      expect(UserRole.tryFromWireName(null), isNull);
      expect(UserRole.tryFromWireName(''), isNull);
    });

    test('every role has a non-empty permission set', () {
      for (final UserRole role in UserRole.values) {
        expect(
          role.permissions,
          isNotEmpty,
          reason: '${role.wireName} would be unable to do anything',
        );
      }
    });

    test('every role can view the dashboard', () {
      // Otherwise a signed-in user would land on a screen they cannot see and
      // the router would bounce them to /unauthorized with nowhere to go.
      for (final UserRole role in UserRole.values) {
        expect(role.can(Permission.viewDashboard), isTrue);
      }
    });
  });

  group('permission matrix', () {
    test('Super Admin holds every permission', () {
      expect(
        UserRole.superAdmin.permissions,
        Permission.values.toSet(),
        reason: 'a permission exists that Super Admin cannot exercise',
      );
    });

    test('Assessment Admin holds exactly its documented set', () {
      expect(UserRole.assessmentAdmin.permissions, <Permission>{
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
        Permission.exportReports,
      });
    });

    test('Supervisor holds exactly its documented set', () {
      expect(UserRole.supervisor.permissions, <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.viewStudents,
        Permission.viewAssessments,
        Permission.reviewScanQuality,
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
      });
    });

    test('PST Teacher holds exactly its documented set', () {
      expect(UserRole.pstTeacher.permissions, <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.viewStudents,
        Permission.viewAssessments,
        Permission.conductAssessment,
        Permission.captureOmr,
        Permission.processOmr,
        Permission.reviewScanQuality,
        Permission.viewOmrImage,
        Permission.viewResults,
        Permission.viewOwnSubmissions,
        Permission.syncSubmissions,
      });
    });

    test('Scanner Operator holds exactly its documented set', () {
      expect(UserRole.scannerOperator.permissions, <Permission>{
        Permission.viewDashboard,
        Permission.viewAssessments,
        Permission.captureOmr,
        Permission.processOmr,
        Permission.reviewScanQuality,
        Permission.viewOmrImage,
        Permission.viewOwnSubmissions,
        Permission.syncSubmissions,
      });
    });

    test('Viewer is read-only', () {
      expect(UserRole.viewer.permissions, <Permission>{
        Permission.viewDashboard,
        Permission.viewSchools,
        Permission.viewStudents,
        Permission.viewAssessments,
        Permission.viewResults,
        Permission.viewAnalytics,
        Permission.viewQuestionAnalytics,
        Permission.exportReports,
      });
      // Nothing that changes state.
      for (final Permission permission in <Permission>[
        Permission.manageStudents,
        Permission.manageAssessments,
        Permission.manageAnswerKey,
        Permission.captureOmr,
        Permission.processOmr,
        Permission.validateOmr,
        Permission.correctScore,
        Permission.resolveSyncConflict,
        Permission.calibrateScanner,
      ]) {
        expect(UserRole.viewer.can(permission), isFalse);
      }
    });
  });

  group('critical restrictions', () {
    test('only Super Admin may correct a score', () {
      // Critical Rule 5: no silent score edits. A correction supersedes a
      // result and is audited, and only one role can start that.
      expect(_rolesWith(Permission.correctScore), <UserRole>{
        UserRole.superAdmin,
      });
    });

    test('only Super Admin may change scanner thresholds', () {
      // Requirement section 50: teachers must not be able to change
      // thresholds.
      expect(_rolesWith(Permission.calibrateScanner), <UserRole>{
        UserRole.superAdmin,
      });
      expect(UserRole.pstTeacher.can(Permission.calibrateScanner), isFalse);
      expect(
        UserRole.scannerOperator.can(Permission.calibrateScanner),
        isFalse,
      );
    });

    test('only Super Admin may manage users or system configuration', () {
      expect(_rolesWith(Permission.manageUsers), <UserRole>{
        UserRole.superAdmin,
      });
      expect(_rolesWith(Permission.manageSystemConfig), <UserRole>{
        UserRole.superAdmin,
      });
    });

    test('the image-quality gate can only be waived by a supervising role', () {
      // The person under time pressure in the classroom is exactly the wrong
      // person to be able to admit unreadable evidence.
      expect(_rolesWith(Permission.overrideQualityGate), <UserRole>{
        UserRole.superAdmin,
        UserRole.supervisor,
      });
      expect(UserRole.pstTeacher.can(Permission.overrideQualityGate), isFalse);
      expect(
        UserRole.scannerOperator.can(Permission.overrideQualityGate),
        isFalse,
      );
    });

    test('validation is separated from capture', () {
      // Requirement section 20: a human other than the scanner decides an
      // ambiguous answer. Neither field-capture role may validate.
      expect(UserRole.pstTeacher.can(Permission.validateOmr), isFalse);
      expect(UserRole.scannerOperator.can(Permission.validateOmr), isFalse);
      expect(UserRole.supervisor.can(Permission.validateOmr), isTrue);
    });

    test('sensitive sync conflicts are not resolved by field roles', () {
      expect(_rolesWith(Permission.resolveSyncConflict), <UserRole>{
        UserRole.superAdmin,
        UserRole.supervisor,
      });
    });

    test('only Super Admin reads the audit log', () {
      expect(_rolesWith(Permission.viewAuditLog), <UserRole>{
        UserRole.superAdmin,
      });
    });

    test('roles that manage master data are limited to Super Admin', () {
      for (final Permission permission in <Permission>[
        Permission.manageStates,
        Permission.manageDistricts,
        Permission.manageClusters,
        Permission.manageSchools,
        Permission.manageStudents,
        Permission.importStudents,
      ]) {
        expect(_rolesWith(permission), <UserRole>{
          UserRole.superAdmin,
        }, reason: '${permission.wireName} is too widely granted');
      }
    });
  });

  group('Permission', () {
    test('wire names are unique', () {
      final Set<String> names = Permission.values
          .map((Permission p) => p.wireName)
          .toSet();
      expect(names, hasLength(Permission.values.length));
    });

    test('resolves from wire name, and unknown names grant nothing', () {
      expect(Permission.tryFromWireName('validateOmr'), Permission.validateOmr);
      expect(
        Permission.tryFromWireName('somethingNewerServerSideOnly'),
        isNull,
      );
    });

    test('every permission has an action phrase for error messages', () {
      for (final Permission permission in Permission.values) {
        expect(permission.actionPhrase, isNotEmpty);
        // Phrases are interpolated into "You do not have permission to ...",
        // so they must read as a verb phrase, not a sentence.
        expect(permission.actionPhrase, isNot(endsWith('.')));
        expect(
          permission.actionPhrase[0],
          permission.actionPhrase[0].toLowerCase(),
        );
      }
    });
  });
}

Set<UserRole> _rolesWith(Permission permission) =>
    UserRole.values.where((UserRole role) => role.can(permission)).toSet();
