/// Every screen that shows invented figures must say so.
///
/// The phase-3-to-11 screens are design previews built ahead of their engines,
/// and they are full of plausible-looking numbers. Critical Rule 14 says this
/// product shows no number it has not measured, so each of those screens
/// carries a sample-data band. This test fails if one loses it — which is
/// exactly what could happen when a screen is half-converted to real data.
///
/// As each phase lands, its route moves from [_previewRoutes] to
/// [_realRoutes], and the test then enforces the opposite: no band on a screen
/// that shows measured data.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

import 'role_navigation_test.dart' show goTo;
import 'test_harness.dart';

/// Routes still showing sample data, with the phase that makes them real.
const Map<String, String> _previewRoutes = <String, String>{
  RoutePaths.reports: 'Phase 11',
  RoutePaths.analytics: 'Phase 10',
  RoutePaths.sync: 'Phase 9',
  RoutePaths.omrCapture: 'Phase 5',
  RoutePaths.calibration: 'Phase 6',
};

/// Routes backed by real repositories. These must NOT be banded.
const List<String> _realRoutes = <String>[
  RoutePaths.dashboard,
  RoutePaths.schools,
  RoutePaths.students,
  RoutePaths.users,
  RoutePaths.assessments,
  '/assessments/as_demo_baseline_g5',
  '/assessments/as_demo_baseline_g5/answer-key',
  '/assessment-session/ses_demo_1',
  RoutePaths.settings,
  RoutePaths.omrValidationQueue,
  '/omr/validation/0001827',
  RoutePaths.results,
  '/results?assessmentId=as_demo_midline_g5',
];

final Finder _band = find.textContaining('every figure below is made up');

void main() {
  final List<DemoAccount> allRoles = UserRole.values
      .map(testAccount)
      .toList(growable: false);

  group('preview screens are labelled', () {
    for (final MapEntry<String, String> entry in _previewRoutes.entries) {
      testWidgets('${entry.key} shows the sample-data band', (
        WidgetTester tester,
      ) async {
        final ProviderContainer container = await pumpApp(
          tester,
          accounts: allRoles,
        );
        // Super Admin holds every permission, so no route is refused for a
        // reason unrelated to what this test is checking.
        await signInAs(tester, container, UserRole.superAdmin);
        await goTo(tester, container, entry.key);

        expect(
          _band,
          findsOneWidget,
          reason:
              '${entry.key} shows invented figures without saying so. Either '
              'restore the band, or move the route to _realRoutes once '
              '${entry.value} has wired it to real data.',
        );
      });
    }
  });

  group('screens with real data are not labelled', () {
    for (final String route in _realRoutes) {
      testWidgets('$route carries no sample-data band', (
        WidgetTester tester,
      ) async {
        final ProviderContainer container = await pumpApp(
          tester,
          accounts: allRoles,
        );
        await signInAs(tester, container, UserRole.superAdmin);
        await goTo(tester, container, route);

        expect(
          _band,
          findsNothing,
          reason: '$route reads from a repository, so it must not claim to be '
              'sample data',
        );
      });
    }
  });
}
