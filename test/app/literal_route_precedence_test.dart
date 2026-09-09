/// A literal segment must win against a parameter that could swallow it.
///
/// `/schools/new` and `/schools/:schoolId` both match the location
/// `/schools/new`. If the parameterised one wins, tapping "Add school" opens
/// the *detail* screen for a school whose id is the string `new` — which
/// renders "school not found" rather than a form, and does so without any
/// error that would point at routing.
///
/// The hazard is structural, not hypothetical: `kAppRoutes` is split into
/// shell and top-level routes before being handed to `GoRouter`, and the
/// create-forms are deliberately outside the shell (a form is a task, not a
/// destination) while the detail screens are inside it. That split reorders
/// them relative to declaration order, so the ordering that makes this work
/// is not the ordering anyone reading the route table would see.
///
/// This test pins the behaviour so that adding a `/foo/new` route next to a
/// `/foo/:fooId` one cannot quietly regress.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

import '../widget/role_navigation_test.dart' show goTo;
import '../widget/test_harness.dart';

/// Each literal route, and a phrase only its own screen renders.
const Map<String, String> _literalRoutes = <String, String>{
  RoutePaths.schoolNew: 'Add school',
  RoutePaths.studentNew: 'Add student',
  RoutePaths.studentImport: 'Import students',
  RoutePaths.userNew: 'Add user',
  RoutePaths.assessmentNew: 'New assessment',
};

void main() {
  final List<DemoAccount> allRoles = UserRole.values
      .map(testAccount)
      .toList(growable: false);

  group('a literal path segment beats a parameterised sibling', () {
    for (final MapEntry<String, String> entry in _literalRoutes.entries) {
      testWidgets('${entry.key} opens its own screen', (
        WidgetTester tester,
      ) async {
        final ProviderContainer container = await pumpApp(
          tester,
          accounts: allRoles,
        );
        await signInAs(tester, container, UserRole.superAdmin);
        await goTo(tester, container, entry.key);

        expect(
          find.text(entry.value),
          findsWidgets,
          reason:
              '${entry.key} did not open its own screen. A parameterised '
              'sibling has swallowed it, so the id is the literal string '
              'after the slash.',
        );
        // The detail screens all report this when handed an id that does not
        // exist, which is exactly what a swallowed route produces.
        expect(
          find.textContaining('could not be found'),
          findsNothing,
          reason: '${entry.key} resolved to a detail screen',
        );
      });
    }
  });
}
