/// The single client-side authorization decision point.
///
/// The router, the navigation shell and every screen ask this class rather
/// than inspecting a role directly. Scattering `if (role == superAdmin)` across
/// widgets is how a role check gets forgotten on the one screen that mattered.
///
/// This is a **usability** boundary. Enforcement is `firebase/firestore.rules`
/// plus Cloud Functions; a patched client gets exactly as far as the rules
/// allow it (docs/04-security-model.md).
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';

/// Why an authorization check failed, or that it did not.
enum AuthorizationOutcome {
  allowed,

  /// No signed-in user.
  notAuthenticated,

  /// The user's account has been deactivated.
  accountInactive,

  /// The role does not hold the permission.
  permissionDenied,

  /// The role holds the permission, but the target is outside the user's
  /// geographic scope.
  outOfScope,
}

/// The result of an authorization check.
final class AuthorizationDecision {
  const AuthorizationDecision._(this.outcome, {this.permission});

  const AuthorizationDecision.allowed() : this._(AuthorizationOutcome.allowed);

  const AuthorizationDecision.notAuthenticated()
    : this._(AuthorizationOutcome.notAuthenticated);

  const AuthorizationDecision.accountInactive()
    : this._(AuthorizationOutcome.accountInactive);

  const AuthorizationDecision.permissionDenied(Permission permission)
    : this._(AuthorizationOutcome.permissionDenied, permission: permission);

  const AuthorizationDecision.outOfScope(Permission permission)
    : this._(AuthorizationOutcome.outOfScope, permission: permission);

  final AuthorizationOutcome outcome;

  /// The permission that was being checked, when there was one.
  final Permission? permission;

  bool get isAllowed => outcome == AuthorizationOutcome.allowed;

  bool get isDenied => !isAllowed;

  /// The failure to return from a repository, or `null` when allowed.
  Failure? get failure => switch (outcome) {
    AuthorizationOutcome.allowed => null,
    AuthorizationOutcome.notAuthenticated => AuthFailure.unauthenticated(
      diagnostic: 'authorization check with no session',
    ),
    AuthorizationOutcome.accountInactive => AuthFailure.accountDisabled(
      diagnostic: 'authorization check for inactive account',
    ),
    AuthorizationOutcome.permissionDenied => PermissionFailure.denied(
      action: permission?.actionPhrase,
      diagnostic: 'missing permission ${permission?.wireName}',
    ),
    AuthorizationOutcome.outOfScope => PermissionFailure.outOfScope(
      diagnostic: 'target outside scope for ${permission?.wireName}',
    ),
  };

  @override
  String toString() =>
      'AuthorizationDecision(${outcome.name}, ${permission?.wireName})';
}

/// Evaluates permission and scope together.
final class Authorization {
  const Authorization(this.user);

  /// The signed-in user, or `null` when there is no session.
  final AppUser? user;

  bool get isAuthenticated => user != null;

  /// Checks a permission, and optionally a target the action applies to.
  ///
  /// Both halves are evaluated in a fixed order — authenticated, active,
  /// permitted, in scope — so a denial always reports the *first* reason,
  /// which is the one the user can act on.
  AuthorizationDecision check(Permission permission, {ScopeTarget? target}) {
    final AppUser? current = user;
    if (current == null) {
      return const AuthorizationDecision.notAuthenticated();
    }
    if (!current.isActive) {
      return const AuthorizationDecision.accountInactive();
    }
    if (!current.can(permission)) {
      return AuthorizationDecision.permissionDenied(permission);
    }
    if (target != null && !current.covers(target)) {
      return AuthorizationDecision.outOfScope(permission);
    }
    return const AuthorizationDecision.allowed();
  }

  /// Convenience form for UI visibility decisions.
  bool can(Permission permission, {ScopeTarget? target}) =>
      check(permission, target: target).isAllowed;

  /// Whether the user holds every permission in [permissions].
  bool canAll(Iterable<Permission> permissions, {ScopeTarget? target}) =>
      permissions.every(
        (Permission permission) => can(permission, target: target),
      );

  /// Whether the user holds at least one of [permissions].
  ///
  /// Used for navigation destinations that lead to a screen with several
  /// entry points.
  bool canAny(Iterable<Permission> permissions, {ScopeTarget? target}) =>
      permissions.any(
        (Permission permission) => can(permission, target: target),
      );

  /// Whether the user may act on [target] at all, ignoring any specific
  /// action. Used to filter lists down to the rows a user is allowed to see.
  bool coversTarget(ScopeTarget target) => user?.covers(target) ?? false;
}
