/// Widget tests for the Schools and Students screens: the add/import
/// affordances are gated by permission, not just present for everyone who
/// can view the list (requirement §36 — only show what a role can use).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

import 'role_navigation_test.dart' show goTo;
import 'test_harness.dart';

void main() {
  final List<DemoAccount> allRoles = UserRole.values
      .map(testAccount)
      .toList(growable: false);

  group('Schools screen', () {
    testWidgets('a super admin sees the add-state affordance', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.superAdmin);
      await goTo(tester, container, RoutePaths.schools);

      expect(find.text('Add state'), findsOneWidget);
    });

    testWidgets('a teacher, who can view but not manage, sees no add '
        'affordance', (WidgetTester tester) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);
      await goTo(tester, container, RoutePaths.schools);

      expect(find.text('Add state'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('Students screen', () {
    testWidgets('a super admin sees both import and add-student '
        'affordances', (WidgetTester tester) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.superAdmin);
      await goTo(tester, container, RoutePaths.students);

      expect(find.byTooltip('Import CSV'), findsOneWidget);
      expect(find.text('Add student'), findsOneWidget);
    });

    testWidgets('a teacher can add a student but not bulk-import', (
      WidgetTester tester,
    ) async {
      // The two are separate permissions on purpose: a teacher registers the
      // children in front of them, while a mis-mapped CSV column is a
      // whole-class error. Their grade-section scope still decides which
      // children they can reach.
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.pstTeacher);
      await goTo(tester, container, RoutePaths.students);

      expect(find.text('Add student'), findsOneWidget);
      expect(find.byTooltip('Import CSV'), findsNothing);
    });

    testWidgets('a viewer sees the student list but no mutation '
        'affordance', (WidgetTester tester) async {
      final ProviderContainer container = await pumpApp(
        tester,
        accounts: allRoles,
      );
      await signInAs(tester, container, UserRole.viewer);
      await goTo(tester, container, RoutePaths.students);

      expect(find.text('Students'), findsWidgets);
      expect(find.byTooltip('Import CSV'), findsNothing);
      expect(find.text('Add student'), findsNothing);
    });
  });
}
