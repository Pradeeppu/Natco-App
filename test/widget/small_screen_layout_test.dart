/// Every screen must render without overflowing on a cheap phone.
///
/// The field devices this product targets are not the 400dp-wide surface the
/// other widget tests use. A 320dp-wide screen is still common on the budget
/// Android handsets used in schools, and a `RenderFlex overflowed` stripe on
/// the validation screen is not a cosmetic problem — it is a decision a
/// Supervisor cannot read.
///
/// Flutter reports an overflow as a framework exception, so
/// `tester.takeException()` catches it here rather than it only showing up as
/// yellow-and-black hatching on a device nobody has plugged in. That this
/// actually works was verified by forcing a 200dp surface, where the
/// dashboard overflowed by 89 pixels and the test failed as it should.
///
/// Screens are also pumped at a large text scale, because a field user
/// reading in sunlight is exactly the person who has turned that up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

import 'role_navigation_test.dart' show goTo;
import 'test_harness.dart';

/// Every route a Super Admin can open, with a concrete id where the path
/// takes one.
const List<String> _allRoutes = <String>[
  RoutePaths.dashboard,
  RoutePaths.schools,
  RoutePaths.schoolNew,
  '/schools/sch_demo_1',
  RoutePaths.students,
  RoutePaths.studentNew,
  RoutePaths.studentImport,
  '/students/stu_demo_001',
  RoutePaths.users,
  RoutePaths.userNew,
  '/users/demo_teacher',
  RoutePaths.assessments,
  RoutePaths.assessmentNew,
  '/assessments/as_demo_baseline_g5',
  '/assessments/as_demo_baseline_g5/answer-key',
  // The draft assessment: its answer-key screen renders the editable grid
  // rather than the read-only view, which is a different layout.
  '/assessments/as_demo_baseline_g7/answer-key',
  '/assessment-session/ses_demo_1',
  RoutePaths.omrCapture,
  '/omr/capture?sessionId=ses_demo_1',
  '/omr/review/0001827',
  RoutePaths.omrValidationQueue,
  '/omr/validation/0001827',
  RoutePaths.results,
  '/results/stu_demo_001',
  RoutePaths.analytics,
  RoutePaths.reports,
  RoutePaths.sync,
  RoutePaths.settings,
  RoutePaths.calibration,
];

/// 320 x 640 is a genuinely small budget handset; 360 x 640 is the most
/// common Android width in the field.
const List<Size> _surfaces = <Size>[Size(320, 640), Size(360, 640)];

void main() {
  final List<DemoAccount> allRoles = UserRole.values
      .map(testAccount)
      .toList(growable: false);

  for (final Size surface in _surfaces) {
    group('${surface.width.toInt()}dp wide', () {
      for (final String route in _allRoutes) {
        testWidgets('$route renders without overflowing', (
          WidgetTester tester,
        ) async {
          final ProviderContainer container = await pumpApp(
            tester,
            accounts: allRoles,
            surfaceSize: surface,
          );
          await signInAs(tester, container, UserRole.superAdmin);
          await goTo(tester, container, route);

          expect(
            tester.takeException(),
            isNull,
            reason:
                '$route overflows at ${surface.width.toInt()}dp — it would '
                'show the overflow stripe on a budget handset',
          );
        });
      }
    });
  }

  group('large text', () {
    // A field user reading in daylight turns text size up. At 1.3x the
    // layout must still hold; beyond that Flutter's own widgets start to
    // break, which is not something this project can fix.
    for (final String route in <String>[
      RoutePaths.dashboard,
      RoutePaths.students,
      RoutePaths.omrValidationQueue,
      '/omr/validation/0001827',
      RoutePaths.sync,
    ]) {
      testWidgets('$route holds at 1.3x text scale', (
        WidgetTester tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final ProviderContainer container = await pumpApp(
          tester,
          accounts: allRoles,
          surfaceSize: const Size(360, 640),
        );
        await signInAs(tester, container, UserRole.superAdmin);
        await goTo(tester, container, route);

        expect(
          tester.takeException(),
          isNull,
          reason: '$route overflows at 1.3x text scale',
        );
      });
    }
  });
}
