/// Tests for the role-filtered navigation destinations.
///
/// The property under test is requirement section 36: only the screens allowed
/// for the user's role are shown. A visible destination that leads to
/// /unauthorized would be a bug the user experiences as the app lying to them,
/// so the last test here checks the bar against the route table directly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/navigation.dart';
import 'package:natco_app/app/route_guard.dart';
import 'package:natco_app/app/router.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';

Authorization _as(UserRole role) => Authorization(
  AppUser(
    userId: 'u1',
    email: 'user@natco.test',
    displayName: 'Test User',
    role: role,
    scope: const AccessScope.global(),
    isActive: true,
  ),
);

List<String> _labels(UserRole role) =>
    visibleDestinations(_as(role))
        .map((NavDestination d) => d.label)
        .toList(growable: false);

void main() {
  group('visibleDestinations', () {
    test('shows nothing when there is no session', () {
      expect(visibleDestinations(const Authorization(null)), isEmpty);
    });

    test('gives a Super Admin every destination', () {
      expect(
        visibleDestinations(_as(UserRole.superAdmin)),
        hasLength(kNavDestinations.length),
      );
    });

    test('gives a teacher a short, field-oriented bar', () {
      final List<String> labels = _labels(UserRole.pstTeacher);
      expect(labels, <String>[
        'Dashboard',
        'Schools',
        'Students',
        'Assessments',
        'OMR',
        'Results',
        // Report cards for the teacher's own class, per the role brief. Their
        // scope still decides *whose* cards; the destination only decides
        // whether the screen is reachable.
        'Reports',
        'Sync',
      ]);
      expect(labels, isNot(contains('Validation')));
      expect(labels, isNot(contains('Analytics')));
      // Reports *is* present — a teacher prints report cards for their own
      // class. Analytics is not: cross-school comparison is a supervising
      // job, and it is a different permission.
      expect(labels, isNot(contains('Users')));
    });

    test('gives a scanner operator only what they operate', () {
      // Assessments is present because the operator must know which
      // assessment a sheet belongs to; nothing about master data,
      // validation, results or analytics is.
      expect(_labels(UserRole.scannerOperator), <String>[
        'Dashboard',
        'Assessments',
        'OMR',
        'Sync',
      ]);
      for (final String hidden in <String>[
        'Schools',
        'Students',
        'Validation',
        'Results',
        'Analytics',
        'Reports',
      ]) {
        expect(_labels(UserRole.scannerOperator), isNot(contains(hidden)));
      }
    });

    test('gives a Supervisor monitoring destinations, not capture', () {
      final List<String> labels = _labels(UserRole.supervisor);
      expect(labels, contains('Validation'));
      expect(labels, contains('Analytics'));
      expect(labels, contains('Sync'));
      expect(
        labels,
        isNot(contains('OMR')),
        reason: 'a Supervisor reviews sheets, they do not capture them',
      );
    });

    test('gives a Viewer read-only destinations', () {
      expect(_labels(UserRole.viewer), <String>[
        'Dashboard',
        'Schools',
        'Students',
        'Assessments',
        'Results',
        'Analytics',
        'Reports',
      ]);
      expect(_labels(UserRole.viewer), isNot(contains('Sync')));
      expect(_labels(UserRole.viewer), isNot(contains('OMR')));
    });

    test('gives an Assessment Admin no OMR or validation destinations', () {
      final List<String> labels = _labels(UserRole.assessmentAdmin);
      expect(labels, contains('Assessments'));
      expect(labels, contains('Reports'));
      expect(labels, isNot(contains('OMR')));
      expect(labels, isNot(contains('Validation')));
      expect(labels, isNot(contains('Sync')));
    });

    test('every role sees the dashboard first', () {
      for (final UserRole role in UserRole.values) {
        expect(_labels(role).first, 'Dashboard', reason: role.wireName);
      }
    });

    test('preserves the declared order', () {
      // Order is the requirement's own (section 36), so filtering must not
      // reshuffle it.
      for (final UserRole role in UserRole.values) {
        final List<NavDestination> visible = visibleDestinations(_as(role));
        final List<int> indices = visible
            .map(kNavDestinations.indexOf)
            .toList(growable: false);
        final List<int> sorted = List<int>.of(indices)..sort();
        expect(indices, sorted, reason: role.wireName);
      }
    });
  });

  group('selectedDestinationIndex', () {
    final List<NavDestination> destinations = visibleDestinations(
      _as(UserRole.superAdmin),
    );

    test('matches an exact path', () {
      expect(
        destinations[selectedDestinationIndex(
              destinations,
              RoutePaths.students,
            )]
            .label,
        'Students',
      );
    });

    test('matches a child path, so a detail screen stays highlighted', () {
      expect(
        destinations[selectedDestinationIndex(destinations, '/schools/sch1')]
            .label,
        'Schools',
      );
    });

    test('falls back to the first destination for an unknown path', () {
      expect(selectedDestinationIndex(destinations, '/settings'), 0);
    });

    test('does not treat a shared prefix as a match', () {
      // `/students` must not match `/students-archive`.
      final int index = selectedDestinationIndex(
        destinations,
        '/students-archive',
      );
      expect(destinations[index].label, 'Dashboard');
    });

    test('handles an empty destination list without throwing', () {
      expect(
        selectedDestinationIndex(const <NavDestination>[], '/anything'),
        0,
      );
    });
  });

  group('destinations agree with the route table', () {
    test('every destination route is a registered route', () {
      final Set<String> registered = kAppRoutes
          .map((GuardedRoute r) => r.path)
          .toSet();
      for (final NavDestination destination in kNavDestinations) {
        expect(
          registered,
          contains(destination.route),
          reason: '${destination.label} points at an unregistered route',
        );
      }
    });

    test('no visible destination leads to the unauthorized screen', () {
      // The bar and the guard must not be able to disagree.
      for (final UserRole role in UserRole.values) {
        final Authorization authorization = _as(role);
        for (final NavDestination destination in visibleDestinations(
          authorization,
        )) {
          final RouteAccessRule? rule = ruleForMatchedPath(destination.route);
          expect(rule, isNotNull, reason: destination.route);
          expect(
            rule!.access == RouteAccess.permission
                ? authorization.can(rule.permission!)
                : true,
            isTrue,
            reason:
                '${role.wireName} is shown ${destination.label} but cannot '
                'open it',
          );
        }
      }
    });
  });
}
