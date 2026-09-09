/// Smoke tests driving the real Assessments screens against the seeded demo
/// dataset, through the real app wiring.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

import 'test_harness.dart';

void main() {
  testWidgets('a Super Admin browses assessments seeded by the demo dataset', (
    WidgetTester tester,
  ) async {
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
    );
    await signInAs(tester, container, UserRole.superAdmin);

    await tester.tap(find.text('Assessments'));
    await tester.pumpAndSettle();

    expect(find.text('Term 1 Mathematics Assessment'), findsOneWidget);
    expect(find.text('Term 1 English Assessment'), findsOneWidget);

    await tester.tap(find.text('Term 1 English Assessment'));
    await tester.pumpAndSettle();

    // The demo dataset seeds this one already corrected to v2.
    expect(find.text('Key v2'), findsOneWidget);

    await tester.tap(find.text('Manage answer key'));
    await tester.pumpAndSettle();

    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);
    expect(find.text('Superseded'), findsOneWidget);
    expect(find.textContaining('Reason:'), findsOneWidget);
  });

  testWidgets(
    'a v1 key publishes and becomes immutable; a correction produces v2 with a reason and supersedes v1',
    (WidgetTester tester) async {
      final container = await pumpApp(
        tester,
        accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
      );
      await signInAs(tester, container, UserRole.superAdmin);

      await tester.tap(find.text('Assessments'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Assessment name'),
        'Science Quiz',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Assessment code'),
        'SCI-Q1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Academic year'),
        '2026-27',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Grade'),
        '6',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'),
        'Science',
      );
      // Questions (10), Duration (45) and Answer options (A, B, C, D) keep
      // their pre-filled defaults.
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Science Quiz');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Science Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('No answer key'), findsOneWidget);

      await tester.tap(find.text('Manage answer key'));
      await tester.pumpAndSettle();

      // First publish: no change-reason field is shown at all.
      await tester.tap(find.text('Publish answer key'));
      await tester.pumpAndSettle();
      expect(find.text('Reason for change'), findsNothing);

      await tester.enterText(
        find.byType(TextField).first,
        'A,B,C,D,A,B,C,D,A,B',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('Version 1'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);

      // The key is immutable now: the action has become a correction, which
      // requires a reason.
      expect(find.text('Correct answer key'), findsOneWidget);
      await tester.tap(find.text('Correct answer key'));
      await tester.pumpAndSettle();
      expect(find.text('Reason for change'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'A,B,C,D,A,B,C,D,A,A',
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Question 10 answer sheet was misprinted.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Publish correction'));
      await tester.pumpAndSettle();

      expect(find.text('Version 2'), findsOneWidget);
      expect(find.text('Superseded'), findsOneWidget);
      expect(
        find.textContaining('Question 10 answer sheet was misprinted.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a correction is rejected without a change reason',
    (WidgetTester tester) async {
      final container = await pumpApp(
        tester,
        accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
      );
      await signInAs(tester, container, UserRole.superAdmin);

      await tester.tap(find.text('Assessments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Term 1 English Assessment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage answer key'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Correct answer key'));
      await tester.pumpAndSettle();

      // Change the answers but leave the reason blank.
      await tester.enterText(
        find.byType(TextField).first,
        'A,B,B,D,A',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Publish correction'));
      await tester.pumpAndSettle();

      expect(find.textContaining('a reason is required'), findsOneWidget);
    },
  );
}
