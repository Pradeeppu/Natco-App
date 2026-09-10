/// Tests for the route table's completeness.
///
/// Two invariants: every path declared in [RoutePaths] is registered exactly
/// once, and every registered route resolves to an access rule. Together with
/// the guard's fail-closed default, that closes the gap where a screen exists
/// but nobody decided who may see it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/route_guard.dart';
import 'package:natco_app/app/router.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

/// The paths requirement section 57 lists, plus the two the app adds.
const List<String> _declaredPaths = <String>[
  RoutePaths.splash,
  RoutePaths.login,
  RoutePaths.unauthorized,
  RoutePaths.dashboard,
  RoutePaths.schools,
  RoutePaths.schoolDetail,
  RoutePaths.students,
  RoutePaths.studentDetail,
  RoutePaths.assessments,
  RoutePaths.assessmentDetail,
  RoutePaths.answerKey,
  RoutePaths.sessions,
  RoutePaths.assessmentSession,
  RoutePaths.omrCapture,
  RoutePaths.omrReview,
  RoutePaths.omrValidationQueue,
  RoutePaths.omrValidationDetail,
  RoutePaths.results,
  RoutePaths.studentResult,
  RoutePaths.analytics,
  RoutePaths.reports,
  RoutePaths.sync,
  RoutePaths.settings,
  RoutePaths.calibration,
];

void main() {
  group('route table', () {
    test('registers every declared path exactly once', () {
      final List<String> registered = kAppRoutes
          .map((GuardedRoute r) => r.path)
          .toList(growable: false);
      expect(
        registered.toSet(),
        hasLength(registered.length),
        reason: 'a path is registered twice',
      );
      for (final String path in _declaredPaths) {
        expect(registered, contains(path), reason: '$path has no route');
      }
    });

    test('registers nothing beyond the declared paths', () {
      for (final GuardedRoute route in kAppRoutes) {
        expect(
          _declaredPaths,
          contains(route.path),
          reason: '${route.path} is registered but undeclared',
        );
      }
    });

    test('every route resolves to an access rule', () {
      for (final GuardedRoute route in kAppRoutes) {
        expect(
          ruleForMatchedPath(route.path),
          isNotNull,
          reason: '${route.path} would fail closed at runtime',
        );
      }
    });

    test('an unregistered path resolves to no rule', () {
      expect(ruleForMatchedPath('/not/a/route'), isNull);
    });

    test('only splash and login are public', () {
      final Set<String> public = kAppRoutes
          .where((GuardedRoute r) => r.rule.access == RouteAccess.public)
          .map((GuardedRoute r) => r.path)
          .toSet();
      expect(public, <String>{RoutePaths.splash, RoutePaths.login});
      expect(public, RouteGuard.publicLocations);
    });

    test('only settings and the unauthorized screen are role-agnostic', () {
      final Set<String> authenticatedOnly = kAppRoutes
          .where((GuardedRoute r) => r.rule.access == RouteAccess.authenticated)
          .map((GuardedRoute r) => r.path)
          .toSet();
      expect(authenticatedOnly, <String>{
        RoutePaths.unauthorized,
        RoutePaths.settings,
      });
    });

    test('every other route names a specific permission', () {
      for (final GuardedRoute route in kAppRoutes) {
        if (route.rule.access == RouteAccess.permission) {
          expect(
            route.rule.permission,
            isNotNull,
            reason: '${route.path} requires a permission but names none',
          );
        }
      }
    });
  });

  group('permission choices per route', () {
    test('answer-key editing requires manageAnswerKey', () {
      // Critical Rule 6. Viewing an assessment is not editing its key.
      expect(
        ruleForMatchedPath(RoutePaths.answerKey)!.permission,
        Permission.manageAnswerKey,
      );
    });

    test('the validation queue requires validateOmr', () {
      expect(
        ruleForMatchedPath(RoutePaths.omrValidationQueue)!.permission,
        Permission.validateOmr,
      );
      expect(
        ruleForMatchedPath(RoutePaths.omrValidationDetail)!.permission,
        Permission.validateOmr,
      );
    });

    test('calibration requires calibrateScanner', () {
      expect(
        ruleForMatchedPath(RoutePaths.calibration)!.permission,
        Permission.calibrateScanner,
      );
    });

    test('capture requires captureOmr', () {
      expect(
        ruleForMatchedPath(RoutePaths.omrCapture)!.permission,
        Permission.captureOmr,
      );
    });
  });

  group('shell membership', () {
    test('full-screen tasks are outside the navigation shell', () {
      // A user should not be able to wander off mid-capture or mid-validation
      // by tapping the bottom bar.
      for (final String path in <String>[
        RoutePaths.omrValidationDetail,
        RoutePaths.omrReview,
        RoutePaths.assessmentSession,
        RoutePaths.answerKey,
        RoutePaths.omrCapture,
      ]) {
        final GuardedRoute route = kAppRoutes.firstWhere(
          (GuardedRoute r) => r.path == path,
        );
        expect(
          route.insideShell,
          isFalse,
          reason: '$path should be a full-screen task',
        );
      }
    });

    test('the dashboard is inside the shell', () {
      final GuardedRoute route = kAppRoutes.firstWhere(
        (GuardedRoute r) => r.path == RoutePaths.dashboard,
      );
      expect(route.insideShell, isTrue);
    });

    test('public routes are never inside the shell', () {
      // The shell renders navigation, which needs a session.
      for (final GuardedRoute route in kAppRoutes) {
        if (route.rule.access == RouteAccess.public) {
          expect(route.insideShell, isFalse, reason: route.path);
        }
      }
    });
  });

  group('reachability', () {
    test('every role can reach at least one route beyond settings', () {
      for (final UserRole role in UserRole.values) {
        final Iterable<GuardedRoute> reachable = kAppRoutes.where(
          (GuardedRoute r) =>
              r.rule.access == RouteAccess.permission &&
              role.can(r.rule.permission!),
        );
        expect(
          reachable,
          isNotEmpty,
          reason: '${role.wireName} has nowhere to go',
        );
      }
    });
  });
}
