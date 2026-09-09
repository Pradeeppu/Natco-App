/// Who may create which account, and with how much reach.
///
/// `Permission.manageUsers` answers only "may this person touch accounts at
/// all". Two further questions decide whether a specific account may be
/// created, and both have to be answered *here* rather than in a form widget,
/// because a form is exactly what an attacker skips:
///
/// 1. **Which role?** A Supervisor holds `manageUsers` so they can staff their
///    own clusters with PST Teachers. Nothing stops that permission, on its
///    own, from creating a second Super Admin — and a Super Admin has no scope
///    to be outside of, so no geographic check would catch it either. That is
///    a one-tap total escalation, and [UserRole.assignableRoles] is what
///    closes it.
///
/// 2. **How much reach?** A cluster Supervisor must not create a teacher who
///    can see the neighbouring district. A granted scope is checked against
///    the actor's own, using *resolved* ancestry — see [checkScopeGrant] for
///    why the ancestry has to be resolved rather than assumed.
///
/// Pure Dart and free of repositories so the whole policy is unit-testable
/// with no backend (docs/01-architecture.md). Mirrored server-side in
/// `firebase/firestore.rules`; this half is for usability, that half is the
/// enforcement.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/users/domain/entity/user_draft.dart';

abstract final class UserProvisioningPolicy {
  /// The roles [actor] may pick from, for a role dropdown.
  ///
  /// Empty when the actor cannot manage users at all, so a UI built from this
  /// list cannot offer an option the policy would then refuse.
  static List<UserRole> assignableRolesFor(AppUser? actor) {
    if (actor == null || !actor.isActive || !actor.can(Permission.manageUsers)) {
      return const <UserRole>[];
    }
    // Ordered by UserRole declaration rather than by the set's iteration
    // order, so the dropdown reads the same way every time.
    return UserRole.values
        .where(actor.role.canAssign)
        .toList(growable: false);
  }

  /// Whether [actor] may create an account holding [role].
  static Failure? checkRoleGrant({
    required AppUser? actor,
    required UserRole role,
  }) {
    if (actor == null) {
      return AuthFailure.unauthenticated(
        diagnostic: 'user provisioning with no session',
      );
    }
    if (!actor.isActive) {
      return AuthFailure.accountDisabled(
        diagnostic: 'user provisioning by inactive account',
      );
    }
    if (!actor.can(Permission.manageUsers)) {
      return PermissionFailure.denied(
        action: Permission.manageUsers.actionPhrase,
        diagnostic: 'missing manageUsers',
      );
    }
    if (!actor.role.canAssign(role)) {
      return ValidationFailure(
        userMessage:
            'You cannot create a ${role.displayName} account. '
            '${_assignableSentence(actor)}',
        fieldErrors: <String, String>{
          'role': 'Not a role you can assign.',
        },
        diagnostic:
            '${actor.role.wireName} attempted to assign ${role.wireName}',
      );
    }
    return null;
  }

  /// Whether [actor] may grant [granted], given the ancestry of every school
  /// the granted scope names.
  ///
  /// [resolvedSchoolTargets] must hold one fully-populated [ScopeTarget] per
  /// entry in `granted.schoolIds`. That resolution cannot happen inside this
  /// method, and it cannot be skipped: [AccessScope.covers] matches a
  /// cluster-scoped actor against a school by reading the school's
  /// `clusterId`, so a target built from the school id alone would report "not
  /// covered" for a school the actor genuinely owns — and, worse, a caller who
  /// then "fixed" that by relaxing the check would have removed the boundary
  /// entirely. The caller looks the schools up; this method decides.
  static Failure? checkScopeGrant({
    required AppUser? actor,
    required AccessScope granted,
    required List<ScopeTarget> resolvedSchoolTargets,
  }) {
    if (actor == null) {
      return AuthFailure.unauthenticated(
        diagnostic: 'scope grant with no session',
      );
    }
    if (!granted.isValid) {
      return const ValidationFailure(
        userMessage:
            'Choose at least one school for this person. An account with no '
            'schools cannot see anything.',
        fieldErrors: <String, String>{'scope': 'Select at least one school.'},
        diagnostic: 'granted scope has no defining ids',
      );
    }

    // A Super Admin is the only role whose own reach is unbounded, so it is
    // the only role that can hand out reach above school level.
    if (actor.scope.isGlobal) {
      return null;
    }

    if (granted.level != ScopeLevel.school) {
      return ValidationFailure(
        userMessage:
            'You can only give someone access to specific schools within your '
            'own area. Wider access has to be set up by a Super Admin.',
        fieldErrors: const <String, String>{
          'scope': 'Choose schools rather than a whole region.',
        },
        diagnostic:
            '${actor.role.wireName} attempted to grant '
            '${granted.level.wireName} scope',
      );
    }

    final Set<String> resolvedIds = <String>{
      for (final ScopeTarget target in resolvedSchoolTargets)
        if (target.schoolId != null) target.schoolId!,
    };
    final Set<String> unresolved = granted.schoolIds.difference(resolvedIds);
    if (unresolved.isNotEmpty) {
      // Refusing rather than skipping: a school whose ancestry could not be
      // read is a school we cannot prove the actor owns, and "could not check"
      // must never resolve to "allowed".
      return PermissionFailure.outOfScope(
        diagnostic: 'unresolved schools in grant: ${unresolved.length}',
      );
    }

    for (final ScopeTarget target in resolvedSchoolTargets) {
      if (!actor.covers(target)) {
        return PermissionFailure.outOfScope(
          diagnostic: 'granted school outside actor scope',
        );
      }
    }
    return null;
  }

  /// Both checks, in the order a form fills its fields.
  static Failure? checkDraft({
    required AppUser? actor,
    required UserDraft draft,
    required List<ScopeTarget> resolvedSchoolTargets,
  }) =>
      checkRoleGrant(actor: actor, role: draft.role) ??
      checkScopeGrant(
        actor: actor,
        granted: draft.scope,
        resolvedSchoolTargets: resolvedSchoolTargets,
      );

  static String _assignableSentence(AppUser actor) {
    final List<UserRole> assignable = UserRole.values
        .where(actor.role.canAssign)
        .toList(growable: false);
    if (assignable.isEmpty) {
      return 'Your role cannot create accounts.';
    }
    if (assignable.length == 1) {
      return 'You can create ${assignable.single.displayName} accounts.';
    }
    return 'You can create: '
        '${assignable.map((UserRole r) => r.displayName).join(', ')}.';
  }
}
