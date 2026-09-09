/// Tests for the combined permission-and-scope decision.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';

AppUser _user({
  required UserRole role,
  required AccessScope scope,
  bool isActive = true,
}) => AppUser(
  userId: 'u1',
  email: 'user@natco.test',
  displayName: 'Test User',
  role: role,
  scope: scope,
  isActive: isActive,
);

void main() {
  group('with no session', () {
    const Authorization authorization = Authorization(null);

    test('denies everything', () {
      expect(authorization.isAuthenticated, isFalse);
      for (final Permission permission in Permission.values) {
        expect(authorization.can(permission), isFalse);
      }
    });

    test('reports not-authenticated, not permission-denied', () {
      // The user can act on "sign in"; they cannot act on "ask an admin".
      final AuthorizationDecision decision = authorization.check(
        Permission.viewDashboard,
      );
      expect(decision.outcome, AuthorizationOutcome.notAuthenticated);
      expect(decision.failure, isA<AuthFailure>());
      expect(decision.failure!.code, FailureCode.unauthenticated);
    });
  });

  group('with a deactivated account', () {
    final Authorization authorization = Authorization(
      _user(
        role: UserRole.superAdmin,
        scope: const AccessScope.global(),
        isActive: false,
      ),
    );

    test('denies even a Super Admin', () {
      expect(authorization.can(Permission.manageUsers), isFalse);
    });

    test('reports the deactivation rather than a missing permission', () {
      final AuthorizationDecision decision = authorization.check(
        Permission.manageUsers,
      );
      expect(decision.outcome, AuthorizationOutcome.accountInactive);
      expect(decision.failure!.code, FailureCode.accountDisabled);
    });
  });

  group('permission before scope', () {
    final Authorization teacher = Authorization(
      _user(role: UserRole.pstTeacher, scope: AccessScope.singleSchool('sch1')),
    );

    test('a missing permission is reported even for an in-scope target', () {
      // The first thing actually wrong is reported, so the message the user
      // sees is the one they can act on.
      final AuthorizationDecision decision = teacher.check(
        Permission.validateOmr,
        target: const ScopeTarget(schoolId: 'sch1'),
      );
      expect(decision.outcome, AuthorizationOutcome.permissionDenied);
      expect(decision.permission, Permission.validateOmr);
    });

    test('a held permission on an out-of-scope target reports the scope', () {
      final AuthorizationDecision decision = teacher.check(
        Permission.captureOmr,
        target: const ScopeTarget(schoolId: 'sch2'),
      );
      expect(decision.outcome, AuthorizationOutcome.outOfScope);
      expect(decision.failure!.code, FailureCode.outOfScope);
      expect(
        decision.failure!.userMessage,
        'You do not have access to this school.',
      );
    });

    test('allows a held permission on an in-scope target', () {
      expect(
        teacher
            .check(
              Permission.captureOmr,
              target: const ScopeTarget(schoolId: 'sch1'),
            )
            .isAllowed,
        isTrue,
      );
    });

    test('omitting the target checks the permission only', () {
      expect(teacher.can(Permission.captureOmr), isTrue);
      expect(teacher.can(Permission.validateOmr), isFalse);
    });
  });

  group('canAll and canAny', () {
    final Authorization supervisor = Authorization(
      _user(
        role: UserRole.supervisor,
        scope: const AccessScope(
          level: ScopeLevel.cluster,
          clusterIds: <String>{'cl1'},
        ),
      ),
    );

    test('canAll requires every permission', () {
      expect(
        supervisor.canAll(<Permission>[
          Permission.validateOmr,
          Permission.reviewExceptions,
        ]),
        isTrue,
      );
      expect(
        supervisor.canAll(<Permission>[
          Permission.validateOmr,
          Permission.captureOmr,
        ]),
        isFalse,
      );
    });

    test('canAny requires one', () {
      expect(
        supervisor.canAny(<Permission>[
          Permission.captureOmr,
          Permission.validateOmr,
        ]),
        isTrue,
      );
      expect(
        supervisor.canAny(<Permission>[
          Permission.captureOmr,
          Permission.correctScore,
        ]),
        isFalse,
      );
    });

    test('canAny on an empty set grants nothing', () {
      expect(supervisor.canAny(const <Permission>[]), isFalse);
    });
  });

  group('failure messages are safe to display', () {
    final Authorization teacher = Authorization(
      _user(role: UserRole.pstTeacher, scope: AccessScope.singleSchool('sch1')),
    );

    test('name the action in plain language', () {
      final Failure failure = teacher.check(Permission.validateOmr).failure!;
      expect(
        failure.userMessage,
        'You do not have permission to validate OMR sheets.',
      );
    });

    test('carry no technical detail in the user message', () {
      for (final Permission permission in Permission.values) {
        final AuthorizationDecision decision = teacher.check(permission);
        final Failure? failure = decision.failure;
        if (failure == null) {
          continue;
        }
        for (final String forbidden in <String>[
          'Exception',
          'Firebase',
          'null',
          'permission-denied',
          permission.wireName,
        ]) {
          expect(
            failure.userMessage,
            isNot(contains(forbidden)),
            reason: 'technical detail leaked for ${permission.wireName}',
          );
        }
      }
    });

    test('keep the diagnostic separate from the user message', () {
      final Failure failure = teacher.check(Permission.manageUsers).failure!;
      expect(failure.diagnostic, contains('manageUsers'));
      expect(failure.userMessage, isNot(contains('manageUsers')));
    });
  });

  test('coversTarget answers the scope half on its own', () {
    final Authorization teacher = Authorization(
      _user(role: UserRole.pstTeacher, scope: AccessScope.singleSchool('sch1')),
    );
    expect(teacher.coversTarget(const ScopeTarget(schoolId: 'sch1')), isTrue);
    expect(teacher.coversTarget(const ScopeTarget(schoolId: 'sch2')), isFalse);
    expect(
      const Authorization(null)
          .coversTarget(const ScopeTarget(schoolId: 'sch1')),
      isFalse,
    );
  });
}
