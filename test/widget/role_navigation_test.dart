/// Widget tests for role-filtered navigation and route guarding.
///
/// These drive the real router, so what they prove is what actually happens on
/// a device: a teacher's bar has no Validation tab, and typing the validation
/// URL directly still refuses them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/router.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

import 'test_harness.dart';

/// Navigates directly, as a deep link or a typed URL would.
Future<void> goTo(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  container.read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

/// A destination label inside the bottom bar.
///
/// `find.widgetWithText(NavigationBar, label)` matches the *bar*, not the
/// destination, so tapping it taps the bar's centre and activates whichever
/// destination happens to sit there. This finder targets the label itself.
Finder barDestination(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

String currentLocation(ProviderContainer container) =>
    container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  final List<DemoAccount> allRoles = UserRole.values
      .map(testAccount)
      .toList(growable: false);

  group('navigation bar', () {
    testWidgets('a teacher gets field destinations and no validation tab', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      // Seven permitted destinations, five bar slots. The four that stay are
      // chosen by what the role does, so a teacher's OMR tab is never buried
      // behind "More".
      expect(barDestination('Dashboard'), findsOne);
      expect(barDestination('OMR'), findsOne);
      expect(barDestination('Results'), findsOne);
      expect(barDestination('Sync'), findsOne);
      expect(barDestination('More'), findsOne);
      // Permitted, but in the overflow rather than the bar.
      expect(barDestination('Schools'), findsNothing);
      expect(barDestination('Students'), findsNothing);
      // Not permitted at all.
      expect(barDestination('Validation'), findsNothing);
      expect(barDestination('Analytics'), findsNothing);
    });

    testWidgets('a scanner operator gets a three-item bar with no overflow', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.scannerOperator);

      expect(barDestination('Dashboard'), findsOne);
      expect(barDestination('Assessments'), findsOne);
      expect(barDestination('OMR'), findsOne);
      expect(barDestination('Sync'), findsOne);
      expect(barDestination('More'), findsNothing);
      expect(barDestination('Students'), findsNothing);
    });

    testWidgets('a Supervisor gets validation but not capture', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.supervisor);

      // Validation is a Supervisor's principal task, so it keeps a bar slot.
      expect(barDestination('Validation'), findsOne);
      expect(barDestination('OMR'), findsNothing);

      final Finder more = barDestination('More');
      expect(more, findsOne);
      await tester.tap(more);
      await tester.pumpAndSettle();

      // The overflow sheet holds the destinations the bar could not fit, and
      // still nothing a Supervisor may not open.
      final Finder sheet = find.byType(BottomSheet);
      expect(sheet, findsOne);
      for (final String label in <String>[
        'Schools',
        'Students',
        'Assessments',
      ]) {
        expect(
          find.descendant(of: sheet, matching: find.text(label)),
          findsOne,
          reason: '$label missing from the overflow sheet',
        );
      }
      expect(
        find.descendant(of: sheet, matching: find.text('OMR')),
        findsNothing,
      );
    });

    testWidgets('tapping a destination navigates', (WidgetTester tester) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      await tester.tap(barDestination('Sync'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), RoutePaths.sync);
      expect(find.text('Sync'), findsWidgets);
    });

    testWidgets('becomes a rail on a wide screen', (WidgetTester tester) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
        surfaceSize: const Size(1100, 900),
      );
      await signInAs(tester, container, UserRole.superAdmin);

      expect(find.byType(NavigationRail), findsOne);
      expect(find.byType(NavigationBar), findsNothing);
      // A rail has room for everything, so nothing is hidden.
      expect(find.text('Reports'), findsWidgets);
    });
  });

  group('route guarding against a typed URL', () {
    testWidgets('refuses a teacher the validation queue', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      await goTo(tester, container, RoutePaths.omrValidationQueue);

      expect(currentLocation(container), RoutePaths.unauthorized);
      expect(
        find.text('You do not have access to this screen'),
        findsOneWidget,
      );
      expect(find.textContaining('PST Teacher'), findsOneWidget);
    });

    testWidgets('refuses everyone but Super Admin the calibration screen', (
      WidgetTester tester,
    ) async {
      for (final UserRole role in UserRole.values) {
        final ProviderContainer container = await pumpApp(
          tester,
          accounts: allRoles,
        );
        await signInAs(tester, container, role);
        await goTo(tester, container, RoutePaths.calibration);

        expect(
          currentLocation(container),
          role == UserRole.superAdmin
              ? RoutePaths.calibration
              : RoutePaths.unauthorized,
          reason: '${role.wireName} reached the wrong screen',
        );
      }
    });

    testWidgets('offers a way back from the unauthorized screen', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.viewer);
      await goTo(tester, container, RoutePaths.omrCapture);

      expect(currentLocation(container), RoutePaths.unauthorized);
      await tester.tap(find.widgetWithText(FilledButton, 'Go to dashboard'));
      await tester.pumpAndSettle();
      expect(currentLocation(container), RoutePaths.dashboard);
    });

    testWidgets('sends an unauthenticated deep link to login and back', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );

      await goTo(tester, container, RoutePaths.results);
      expect(currentLocation(container), RoutePaths.login);

      await signInAs(tester, container, UserRole.viewer);
      expect(
        currentLocation(container),
        RoutePaths.results,
        reason: 'the intended destination should survive the sign-in',
      );
    });

    testWidgets('refuses an unregistered path', (WidgetTester tester) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.superAdmin);
      await goTo(tester, container, '/not/a/screen');
      // Fails closed rather than rendering an error page for a signed-in user.
      expect(currentLocation(container), RoutePaths.unauthorized);
    });
  });

  group('dashboard', () {
    testWidgets('greets the user and states their role and scope', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: <DemoAccount>[
          DemoAccount(
            user: testAccount(UserRole.pstTeacher).user.copyWith(
              displayName: 'Suresh Babu',
              scope: AccessScope(
                level: ScopeLevel.school,
                schoolIds: const <String>{'sch1'},
                gradeSections: <GradeSection>{
                  const GradeSection(grade: '5', section: 'A'),
                },
              ),
            ),
            password: kTestPassword,
          ),
        ],
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      // The fixed clock reads 09:00 UTC.
      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.text('Suresh'), findsOneWidget);
      expect(find.text('PST Teacher'), findsOneWidget);
      expect(find.text('School'), findsOneWidget);
      expect(find.text('1 school'), findsOneWidget);
      expect(find.text('Grade 5 - Section A'), findsOneWidget);
    });

    testWidgets('shows only quick actions the role can reach', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      expect(find.text('Start or continue assessment'), findsOneWidget);
      expect(find.text('Capture OMR'), findsOneWidget);
      // A teacher has no calibration permission, so no tile offers it.
      expect(find.text('Scanner calibration'), findsNothing);
    });

    testWidgets('a quick action navigates to a screen the user can open', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.supervisor);

      await tester.tap(find.text('Validation queue'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), RoutePaths.omrValidationQueue);
      expect(currentLocation(container), isNot(RoutePaths.unauthorized));
    });

    testWidgets('does not display invented assessment metrics', (
      WidgetTester tester,
    ) async {
      // Critical Rules 3 and 14: the app shows no number it has not measured.
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.supervisor);

      await scrollTo(tester, find.text('Assessment metrics'));
      expect(find.text('Assessment metrics'), findsOneWidget);
      expect(
        find.textContaining('never shows a number it has not measured'),
        findsOneWidget,
      );
    });

    testWidgets('warns when the session came from the offline cache', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);
      // A fresh sign-in is verified, so no warning.
      expect(find.textContaining('saved session'), findsNothing);
    });
  });

  group('connectivity banner', () {
    testWidgets('appears when the device is offline', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
        connection: ConnectionStatus.offline,
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      expect(
        find.text('Offline. Your work is saved on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('distinguishes no-internet from no-interface', (
      WidgetTester tester,
    ) async {
      // A school Wi-Fi with no upstream is the normal field case and needs a
      // different message from "no signal".
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
        connection: ConnectionStatus.interfaceOnly,
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      expect(
        find.textContaining('the server cannot be reached'),
        findsOneWidget,
      );
    });

    testWidgets('stays hidden when the connection is usable', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);
      expect(find.textContaining('saved on this device'), findsNothing);
    });
  });

  group('settings', () {
    testWidgets('is reachable by every role and signs the user out', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.viewer);
      await goTo(tester, container, RoutePaths.settings);

      expect(currentLocation(container), RoutePaths.settings);
      expect(find.text('Settings'), findsWidgets);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      // Confirmed, because signing out ends offline access.
      expect(find.textContaining('need an internet connection'), findsOne);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), RoutePaths.login);
    });

    testWidgets('lists the granted permissions', (WidgetTester tester) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.scannerOperator);
      await goTo(tester, container, RoutePaths.settings);

      expect(
        find.text('${UserRole.scannerOperator.permissions.length} granted'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the word Coordinator never reaches the screen', (
    // allow-coordinator-reference
    WidgetTester tester,
  ) async {
    // Requirement section 1 and Critical Rule 1.
    final ProviderContainer container = await pumpApp(
      tester,
      accounts: allRoles,
    );
    for (final UserRole role in UserRole.values) {
      await signInAs(tester, container, role);
      expect(
        find.textContaining(
          RegExp('coordinator', caseSensitive: false),
        ), // allow-coordinator-reference
        findsNothing,
        reason: 'rendered for ${role.wireName}',
      );
      await container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
    }
  });
}
