/// Route authorization, as pure logic.
///
/// Kept separate from `router.dart` and free of any Flutter or go_router type
/// so that every branch is unit-testable without pumping a widget. The router
/// calls [RouteGuard.redirectFor] from its single `redirect` hook.
///
/// The guard **fails closed**: a route with no declared permission that is not
/// on the explicit public list is treated as forbidden. Adding a screen and
/// forgetting to declare who may see it therefore breaks the screen, rather
/// than exposing it (docs/05-navigation-map.md).
library;

import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

/// What a route requires of the caller.
enum RouteAccess {
  /// Reachable without a session: splash, login.
  public,

  /// Any signed-in user, whatever their role: settings, the unauthorized
  /// screen itself.
  authenticated,

  /// A signed-in user holding a specific permission.
  permission,
}

/// One route's access declaration.
final class RouteAccessRule {
  const RouteAccessRule.public()
    : access = RouteAccess.public,
      permission = null;

  const RouteAccessRule.authenticated()
    : access = RouteAccess.authenticated,
      permission = null;

  const RouteAccessRule.requires(Permission this.permission)
    : access = RouteAccess.permission;

  final RouteAccess access;
  final Permission? permission;
}

/// The query parameter used to carry the location the user was heading to when
/// they were bounced to the login screen.
const String kIntendedLocationParam = 'from';

abstract final class RouteGuard {
  /// Locations that must remain reachable with no session.
  static const Set<String> publicLocations = <String>{
    RoutePaths.splash,
    RoutePaths.login,
  };

  /// Resolves the redirect for a navigation attempt.
  ///
  /// Returns `null` to allow it. Evaluated in a fixed order so that the reason
  /// a user is redirected is always the first thing actually wrong:
  ///
  /// 1. still restoring        -> splash
  /// 2. no session             -> login, remembering where they were going
  /// 3. signed in, on login    -> intended location, else dashboard
  /// 4. account deactivated    -> login
  /// 5. missing permission     -> unauthorized
  static String? redirectFor({
    required SessionState session,
    required String location,
    required RouteAccessRule? rule,
    String? intendedLocation,
  }) {
    final String path = _pathOf(location);

    if (session.isRestoring) {
      return path == RoutePaths.splash ? null : RoutePaths.splash;
    }

    final bool isPublic = publicLocations.contains(path);

    if (!session.isAuthenticated) {
      if (isPublic) {
        // Nothing to restore any more: keep the user on the login screen
        // rather than bouncing them back to a splash that will only send them
        // here again.
        return path == RoutePaths.splash ? RoutePaths.login : null;
      }
      return _loginWithIntendedLocation(location);
    }

    // Signed in. The splash and login screens have no further purpose.
    if (isPublic) {
      final String? target = intendedLocation;
      if (target != null &&
          target.isNotEmpty &&
          !publicLocations.contains(_pathOf(target))) {
        return target;
      }
      return RoutePaths.dashboard;
    }

    final Authorization authorization = session.authorization;

    // An inactive account is signed out rather than shown an empty app. This
    // catches a deactivation that arrived while the session was cached.
    if (!authorization.isAuthenticated ||
        !(session.session?.user.isActive ?? false)) {
      return RoutePaths.login;
    }

    if (path == RoutePaths.unauthorized) {
      return null;
    }

    // Fail closed: an undeclared route is not reachable.
    if (rule == null) {
      return RoutePaths.unauthorized;
    }

    return switch (rule.access) {
      RouteAccess.public || RouteAccess.authenticated => null,
      RouteAccess.permission =>
        authorization.can(rule.permission!) ? null : RoutePaths.unauthorized,
    };
  }

  /// Builds the login location carrying [location] as the intended
  /// destination, so a deep link survives a sign-in.
  static String _loginWithIntendedLocation(String location) {
    final String path = _pathOf(location);
    if (publicLocations.contains(path)) {
      return RoutePaths.login;
    }
    return Uri(
      path: RoutePaths.login,
      queryParameters: <String, String>{kIntendedLocationParam: location},
    ).toString();
  }

  /// Strips the query string and fragment from a location.
  static String _pathOf(String location) {
    final int cut = location.indexOf(RegExp(r'[?#]'));
    return cut == -1 ? location : location.substring(0, cut);
  }
}
