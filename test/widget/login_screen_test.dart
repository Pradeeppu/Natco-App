/// Widget tests for sign-in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

import 'test_harness.dart';

void main() {
  group('login screen', () {
    testWidgets('is where an unauthenticated user lands', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('NATCO Assessment'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email address'), findsOne);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOne);
    });

    testWidgets('validates both fields before making a request', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email address'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      // Still on the login screen: nothing was sent.
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('rejects an address with no @', (WidgetTester tester) async {
      await pumpApp(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'not-an-address',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        kTestPassword,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('shows a plain-language message for wrong credentials', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'pstTeacher@natco.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrong-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(
        find.text('Incorrect email or password. Please check and try again.'),
        findsOneWidget,
      );
      // No technical detail reaches the screen (requirement section 40).
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Failure'), findsNothing);
    });

    testWidgets('does not reveal whether the address exists', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'nobody@natco.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        kTestPassword,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      // The same message as a wrong password, so the form is not an
      // account-enumeration oracle.
      expect(
        find.text('Incorrect email or password. Please check and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('signs in and reaches the dashboard', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'pstTeacher@natco.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        kTestPassword,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('refuses a deactivated account with a clear message', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        accounts: <DemoAccount>[
          testAccount(UserRole.pstTeacher, isActive: false),
        ],
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'pstTeacher@natco.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        kTestPassword,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('This account has been deactivated'),
        findsOneWidget,
      );
    });

    testWidgets('toggles password visibility', (WidgetTester tester) async {
      await pumpApp(tester);
      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('asks for an address before sending a reset link', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter your email address first'),
        findsOneWidget,
      );
    });

    testWidgets('confirms a reset without confirming the address exists', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'nobody@natco.test',
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('If that address has an account'),
        findsOneWidget,
      );
    });

    testWidgets('offers demo accounts in a build with no backend', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        accounts: <DemoAccount>[
          testAccount(UserRole.superAdmin),
          testAccount(UserRole.supervisor),
        ],
      );
      expect(find.text('Demo accounts'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Supervisor'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'Supervisor'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('never renders the word Coordinator', (
      // allow-coordinator-reference
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        accounts: <DemoAccount>[testAccount(UserRole.supervisor)],
      );
      expect(
        find.textContaining('Coordinator'),
        findsNothing,
      ); // allow-coordinator-reference
      expect(
        find.textContaining('coordinator'),
        findsNothing,
      ); // allow-coordinator-reference
    });
  });
}
