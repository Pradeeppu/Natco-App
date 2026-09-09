/// Tests for [UserProvisioningPolicy] — the boundary that stops
/// `Permission.manageUsers` from being a one-tap privilege escalation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/users/domain/entity/user_draft.dart';
import 'package:natco_app/features/users/domain/service/user_provisioning_policy.dart';

AppUser _actor(UserRole role, AccessScope scope) => AppUser(
  userId: 'actor_1',
  email: 'actor@natco.demo',
  displayName: 'Actor',
  role: role,
  scope: scope,
  isActive: true,
);

const _clusterScope = AccessScope(
  level: ScopeLevel.cluster,
  stateIds: <String>{'st_1'},
  districtIds: <String>{'di_1'},
  clusterIds: <String>{'cl_1'},
);

void main() {
  group('assignableRolesFor', () {
    test('is empty with no session', () {
      expect(UserProvisioningPolicy.assignableRolesFor(null), isEmpty);
    });

    test('is empty for an inactive account', () {
      const actor = AppUser(
        userId: 'u1',
        email: 'a@b.com',
        displayName: 'A',
        role: UserRole.superAdmin,
        scope: AccessScope.global(),
        isActive: false,
      );
      expect(UserProvisioningPolicy.assignableRolesFor(actor), isEmpty);
    });

    test('a Super Admin may assign every role', () {
      final actor = _actor(UserRole.superAdmin, const AccessScope.global());
      expect(
        UserProvisioningPolicy.assignableRolesFor(actor).toSet(),
        UserRole.values.toSet(),
      );
    });

    test('a Supervisor may assign only PST Teacher', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      expect(UserProvisioningPolicy.assignableRolesFor(actor), <UserRole>[
        UserRole.pstTeacher,
      ]);
    });

    test('a PST Teacher may assign nobody', () {
      final actor = _actor(
        UserRole.pstTeacher,
        AccessScope.singleSchool('sch_1'),
      );
      expect(UserProvisioningPolicy.assignableRolesFor(actor), isEmpty);
    });
  });

  group('checkRoleGrant', () {
    test('refuses with no session', () {
      expect(
        UserProvisioningPolicy.checkRoleGrant(
          actor: null,
          role: UserRole.pstTeacher,
        ),
        isNotNull,
      );
    });

    test('a Supervisor granting PST Teacher is allowed', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      expect(
        UserProvisioningPolicy.checkRoleGrant(
          actor: actor,
          role: UserRole.pstTeacher,
        ),
        isNull,
      );
    });

    test('a Supervisor cannot mint a Super Admin', () {
      // The one-tap escalation this policy exists to close.
      final actor = _actor(UserRole.supervisor, _clusterScope);
      final failure = UserProvisioningPolicy.checkRoleGrant(
        actor: actor,
        role: UserRole.superAdmin,
      );
      expect(failure, isNotNull);
    });

    test('a Supervisor cannot mint another Supervisor', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      expect(
        UserProvisioningPolicy.checkRoleGrant(
          actor: actor,
          role: UserRole.supervisor,
        ),
        isNotNull,
      );
    });
  });

  group('checkScopeGrant', () {
    test('refuses an empty scope', () {
      final actor = _actor(UserRole.superAdmin, const AccessScope.global());
      final failure = UserProvisioningPolicy.checkScopeGrant(
        actor: actor,
        granted: const AccessScope(level: ScopeLevel.school),
        resolvedSchoolTargets: const <ScopeTarget>[],
      );
      expect(failure, isNotNull);
    });

    test('a Super Admin may grant any level', () {
      final actor = _actor(UserRole.superAdmin, const AccessScope.global());
      final failure = UserProvisioningPolicy.checkScopeGrant(
        actor: actor,
        granted: const AccessScope(
          level: ScopeLevel.state,
          stateIds: <String>{'st_9'},
        ),
        resolvedSchoolTargets: const <ScopeTarget>[],
      );
      expect(failure, isNull);
    });

    test('a non-global actor cannot grant above school level', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      final failure = UserProvisioningPolicy.checkScopeGrant(
        actor: actor,
        granted: const AccessScope(
          level: ScopeLevel.district,
          districtIds: <String>{'di_1'},
        ),
        resolvedSchoolTargets: const <ScopeTarget>[],
      );
      expect(failure, isNotNull);
    });

    test('a Supervisor may grant a school inside their own cluster', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      final granted = AccessScope.singleSchool('sch_1');
      final failure = UserProvisioningPolicy.checkScopeGrant(
        actor: actor,
        granted: granted,
        resolvedSchoolTargets: const <ScopeTarget>[
          ScopeTarget(
            stateId: 'st_1',
            districtId: 'di_1',
            clusterId: 'cl_1',
            schoolId: 'sch_1',
          ),
        ],
      );
      expect(failure, isNull);
    });

    test('a Supervisor cannot grant a school in another cluster', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      final granted = AccessScope.singleSchool('sch_9');
      final failure = UserProvisioningPolicy.checkScopeGrant(
        actor: actor,
        granted: granted,
        resolvedSchoolTargets: const <ScopeTarget>[
          ScopeTarget(
            stateId: 'st_1',
            districtId: 'di_1',
            clusterId: 'cl_9',
            schoolId: 'sch_9',
          ),
        ],
      );
      expect(failure, isNotNull);
    });

    test('an unresolved school is refused, not silently allowed', () {
      // The school id is in the granted scope but has no matching resolved
      // target — this is what "could not verify ownership" looks like, and
      // it must never resolve to "allowed".
      final actor = _actor(UserRole.supervisor, _clusterScope);
      final granted = AccessScope.singleSchool('sch_1');
      final failure = UserProvisioningPolicy.checkScopeGrant(
        actor: actor,
        granted: granted,
        resolvedSchoolTargets: const <ScopeTarget>[],
      );
      expect(failure, isNotNull);
    });
  });

  group('checkDraft', () {
    test('runs the role check before the scope check', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      const draft = UserDraft(
        email: 'x@y.com',
        displayName: 'X',
        role: UserRole.superAdmin,
        scope: AccessScope(level: ScopeLevel.school),
      );
      final failure = UserProvisioningPolicy.checkDraft(
        actor: actor,
        draft: draft,
        resolvedSchoolTargets: const <ScopeTarget>[],
      );
      expect(failure, isNotNull);
    });

    test('a fully valid draft passes both checks', () {
      final actor = _actor(UserRole.supervisor, _clusterScope);
      final draft = UserDraft(
        email: 'x@y.com',
        displayName: 'X',
        role: UserRole.pstTeacher,
        scope: AccessScope.singleSchool('sch_1'),
      );
      final failure = UserProvisioningPolicy.checkDraft(
        actor: actor,
        draft: draft,
        resolvedSchoolTargets: const <ScopeTarget>[
          ScopeTarget(
            stateId: 'st_1',
            districtId: 'di_1',
            clusterId: 'cl_1',
            schoolId: 'sch_1',
          ),
        ],
      );
      expect(failure, isNull);
    });
  });
}
