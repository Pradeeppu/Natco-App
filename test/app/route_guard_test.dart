/// Tests for route authorization.
///
/// The property that matters most is the fail-closed default: a route with no
/// declared access rule must be unreachable, so that adding a screen and
/// forgetting to declare who may see it breaks the screen rather than exposing
/// it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/route_guard.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

SessionState _signedIn(UserRole role, {bool isActive = true}) =>
    SessionAuthenticated(
      AuthSession(
        user: AppUser(
          userId: 'u1',
          email: 'user@natco.test',
          displayName: 'Test User',
          role: role,
          scope: const AccessScope.global(),
          isActive: isActive,
        ),
        establishedAt: DateTime.utc(2026, 9, 1),
        lastVerifiedAt: DateTime.utc(2026, 9, 1),
        origin: SessionOrigin.online,
        deviceId: 'device-1',
      ),
    );

String? _redirect({
  required SessionState session,
  required String location,
  RouteAccessRule? rule,
  String? intendedLocation,
}) => RouteGuard.redirectFor(
  session: session,
  location: location,
  rule: rule,
  intendedLocation: intendedLocation,
);

void main() {
  group('while the session is restoring', () {
    test('holds the user on the splash screen', () {
      expect(
        _redirect(
          session: const SessionRestoring(),
          location: RoutePaths.dashboard,
          rule: const RouteAccessRule.requires(Permission.viewDashboard),
        ),
        RoutePaths.splash,
      );
    });

    test('allows the splash screen itself', () {
      expect(
        _redirect(
          session: const SessionRestoring(),
          location: RoutePaths.splash,
          rule: const RouteAccessRule.public(),
        ),
        isNull,
      );
    });

    test('does not flash the login screen at a signed-in user', () {
      // The point of the restoring state: a user with a cached session must
      // not see /login on the way to /dashboard.
      expect(
        _redirect(
          session: const SessionRestoring(),
          location: RoutePaths.login,
          rule: const RouteAccessRule.public(),
        ),
        RoutePaths.splash,
      );
    });
  });

  group('with no session', () {
    const SessionState session = SessionUnauthenticated();

    test('allows the login screen', () {
      expect(
        _redirect(
          session: session,
          location: RoutePaths.login,
          rule: const RouteAccessRule.public(),
        ),
        isNull,
      );
    });

    test('moves off the splash screen once restoring has finished', () {
      expect(
        _redirect(
          session: session,
          location: RoutePaths.splash,
          rule: const RouteAccessRule.public(),
        ),
        RoutePaths.login,
      );
    });

    test('sends a protected route to login, remembering the destination', () {
      final String? redirect = _redirect(
        session: session,
        location: RoutePaths.dashboard,
        rule: const RouteAccessRule.requires(Permission.viewDashboard),
      );
      expect(redirect, isNotNull);
      final Uri uri = Uri.parse(redirect!);
      expect(uri.path, RoutePaths.login);
      expect(uri.queryParameters[kIntendedLocationParam], RoutePaths.dashboard);
    });

    test('preserves a deep link with its own query string', () {
      const String target = '${RoutePaths.results}?assessment=a1';
      final String? redirect = _redirect(
        session: session,
        location: target,
        rule: const RouteAccessRule.requires(Permission.viewResults),
      );
      expect(
        Uri.parse(redirect!).queryParameters[kIntendedLocationParam],
        target,
      );
    });

    test('does not send an authenticated-only route past the guard', () {
      expect(
        _redirect(
          session: session,
          location: RoutePaths.settings,
          rule: const RouteAccessRule.authenticated(),
        ),
        isNotNull,
      );
    });
  });

  group('after signing in', () {
    test('leaves the login screen for the dashboard', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.pstTeacher),
          location: RoutePaths.login,
          rule: const RouteAccessRule.public(),
        ),
        RoutePaths.dashboard,
      );
    });

    test('returns to the remembered destination', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.supervisor),
          location:
              '${RoutePaths.login}?$kIntendedLocationParam=${RoutePaths.omrValidationQueue}',
          rule: const RouteAccessRule.public(),
          intendedLocation: RoutePaths.omrValidationQueue,
        ),
        RoutePaths.omrValidationQueue,
      );
    });

    test('ignores a remembered destination that is itself public', () {
      // Otherwise a stale `from=/login` would loop.
      expect(
        _redirect(
          session: _signedIn(UserRole.viewer),
          location: RoutePaths.login,
          rule: const RouteAccessRule.public(),
          intendedLocation: RoutePaths.login,
        ),
        RoutePaths.dashboard,
      );
    });

    test('ignores an empty remembered destination', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.viewer),
          location: RoutePaths.login,
          rule: const RouteAccessRule.public(),
          intendedLocation: '',
        ),
        RoutePaths.dashboard,
      );
    });
  });

  group('permission enforcement', () {
    test('allows a route the role permits', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.supervisor),
          location: RoutePaths.omrValidationQueue,
          rule: const RouteAccessRule.requires(Permission.validateOmr),
        ),
        isNull,
      );
    });

    test('refuses a route the role does not permit', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.pstTeacher),
          location: RoutePaths.omrValidationQueue,
          rule: const RouteAccessRule.requires(Permission.validateOmr),
        ),
        RoutePaths.unauthorized,
      );
    });

    test('refuses calibration to everyone but Super Admin', () {
      for (final UserRole role in UserRole.values) {
        final String? redirect = _redirect(
          session: _signedIn(role),
          location: RoutePaths.calibration,
          rule: const RouteAccessRule.requires(Permission.calibrateScanner),
        );
        if (role == UserRole.superAdmin) {
          expect(redirect, isNull);
        } else {
          expect(
            redirect,
            RoutePaths.unauthorized,
            reason: '${role.wireName} reached the calibration screen',
          );
        }
      }
    });

    test('lets any signed-in user reach their own settings', () {
      // Denying this would leave a user with a stale role unable to sign out.
      for (final UserRole role in UserRole.values) {
        expect(
          _redirect(
            session: _signedIn(role),
            location: RoutePaths.settings,
            rule: const RouteAccessRule.authenticated(),
          ),
          isNull,
          reason: '${role.wireName} could not reach settings',
        );
      }
    });

    test('always allows the unauthorized screen itself', () {
      // Otherwise refusing a route would redirect to a refused route.
      expect(
        _redirect(
          session: _signedIn(UserRole.viewer),
          location: RoutePaths.unauthorized,
          rule: const RouteAccessRule.authenticated(),
        ),
        isNull,
      );
    });
  });

  group('fails closed', () {
    test('refuses a route with no declared access rule', () {
      // This is the behaviour that makes a forgotten declaration safe.
      expect(
        _redirect(
          session: _signedIn(UserRole.superAdmin),
          location: '/some/new/screen',
        ),
        RoutePaths.unauthorized,
      );
    });

    test('refuses an undeclared route even for a Super Admin', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.superAdmin),
          location: '/admin/secret',
        ),
        RoutePaths.unauthorized,
      );
    });
  });

  group('a deactivated account', () {
    test('is signed out rather than shown an empty app', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.superAdmin, isActive: false),
          location: RoutePaths.dashboard,
          rule: const RouteAccessRule.requires(Permission.viewDashboard),
        ),
        RoutePaths.login,
      );
    });

    test('cannot reach settings either', () {
      expect(
        _redirect(
          session: _signedIn(UserRole.pstTeacher, isActive: false),
          location: RoutePaths.settings,
          rule: const RouteAccessRule.authenticated(),
        ),
        RoutePaths.login,
      );
    });
  });

  group('an unauthenticated state carrying a reason', () {
    test('still routes to login, so the reason can be shown there', () {
      final SessionState expired = SessionUnauthenticated(
        failure: AuthFailure.sessionExpired(),
      );
      final String? redirect = _redirect(
        session: expired,
        location: RoutePaths.dashboard,
        rule: const RouteAccessRule.requires(Permission.viewDashboard),
      );
      expect(Uri.parse(redirect!).path, RoutePaths.login);
    });
  });

  group('RoutePaths.of', () {
    test('substitutes parameters', () {
      expect(
        RoutePaths.of(RoutePaths.schoolDetail, <String, String>{
          'schoolId': 'sch1',
        }),
        '/schools/sch1',
      );
    });

    test('encodes values so an id with a slash cannot forge a path', () {
      expect(
        RoutePaths.of(RoutePaths.studentDetail, <String, String>{
          'studentId': 'a/b',
        }),
        '/students/a%2Fb',
      );
    });
  });
}
