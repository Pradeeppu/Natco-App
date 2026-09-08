/// Smoke tests driving the real Schools and Students screens against the
/// seeded demo dataset, through the real app wiring.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';

import 'test_harness.dart';

void main() {
  testWidgets('a Super Admin browses the full hierarchy down to a school', (
    WidgetTester tester,
  ) async {
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
    );
    await signInAs(tester, container, UserRole.superAdmin);

    await tester.tap(find.text('Schools and hierarchy'));
    await tester.pumpAndSettle();

    expect(find.text('States'), findsOneWidget);
    expect(find.text('Karnataka'), findsOneWidget);

    await tester.tap(find.text('Karnataka'));
    await tester.pumpAndSettle();
    expect(find.text('Districts'), findsOneWidget);
    expect(find.text('Bengaluru Urban'), findsOneWidget);
    expect(find.text('Mysuru'), findsOneWidget);

    await tester.tap(find.text('Bengaluru Urban'));
    await tester.pumpAndSettle();
    expect(find.text('Clusters'), findsOneWidget);
    expect(find.text('Whitefield'), findsOneWidget);
    expect(find.text('Koramangala'), findsOneWidget);

    await tester.tap(find.text('Whitefield'));
    await tester.pumpAndSettle();
    expect(find.text('Schools'), findsOneWidget);
    expect(find.text('NATCO Public School'), findsOneWidget);

    await tester.tap(find.text('NATCO Public School'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SCH001'), findsWidgets);
    expect(find.text('View students'), findsOneWidget);
  });

  testWidgets('breadcrumbs navigate back up the hierarchy', (
    WidgetTester tester,
  ) async {
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
    );
    await signInAs(tester, container, UserRole.superAdmin);
    await tester.tap(find.text('Schools and hierarchy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Karnataka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bengaluru Urban'));
    await tester.pumpAndSettle();
    expect(find.text('Clusters'), findsOneWidget);

    // Breadcrumb: home icon returns to the root.
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('States'), findsOneWidget);
  });

  testWidgets('search filters the visible list', (WidgetTester tester) async {
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
    );
    await signInAs(tester, container, UserRole.superAdmin);
    await tester.tap(find.text('Schools and hierarchy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karnataka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bengaluru Urban'));
    await tester.pumpAndSettle();

    expect(find.text('Whitefield'), findsOneWidget);
    expect(find.text('Koramangala'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'White');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Whitefield'), findsOneWidget);
    expect(find.text('Koramangala'), findsNothing);
  });

  testWidgets('a teacher scoped to one school lands there with no picker', (
    WidgetTester tester,
  ) async {
    // `testAccount` defaults every role to a global scope, so a real
    // single-school scope has to be built explicitly — and that scope has to
    // name a school that actually exists. Seeding a repository pair directly,
    // outside of any container, and then overriding the app's repository
    // providers with these exact instances sidesteps any question of two
    // separately-seeded datasets agreeing on ids: there is only ever one
    // dataset here, and the app is simply pointed at it.
    const IdGenerator idGenerator = UuidIdGenerator();
    final Clock clock = FixedClock(DateTime.utc(2026, 9, 8, 9));
    final InMemorySchoolsRepository schools = InMemorySchoolsRepository(
      idGenerator: idGenerator,
      clock: clock,
    );
    final InMemoryStudentsRepository students = InMemoryStudentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    seedDemoMasterData(
      schools: schools,
      students: students,
      idGenerator: idGenerator,
      clock: clock,
    );
    final schoolsPage = await schools.listSchools(
      scope: const AccessScope.global(),
    );
    final String schoolId = schoolsPage.valueOrNull!.items.first.schoolId;
    final String schoolName = schoolsPage.valueOrNull!.items.first.schoolName;

    final DemoAccount teacher = DemoAccount(
      user: testAccount(UserRole.pstTeacher).user
          .copyWith(scope: AccessScope.singleSchool(schoolId)),
      password: kTestPassword,
    );
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[teacher],
      extraOverrides: [
        schoolsRepositoryProvider.overrideWithValue(schools),
        studentsRepositoryProvider.overrideWithValue(students),
      ],
    );
    await signInAs(tester, container, UserRole.pstTeacher);

    // Students is reachable straight from the dashboard's quick action, which
    // may sit below the fold on a phone-sized surface.
    await scrollTo(tester, find.text('My students'));
    await tester.tap(find.text('My students'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a school'), findsNothing);
    expect(find.text(schoolName), findsOneWidget);
  });

  testWidgets('a Super Admin adds a student and it appears in the list', (
    WidgetTester tester,
  ) async {
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
    );
    await signInAs(tester, container, UserRole.superAdmin);

    await tester.tap(find.text('Schools and hierarchy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karnataka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bengaluru Urban'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whitefield'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NATCO Public School'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View students'));
    await tester.pumpAndSettle();

    expect(find.text('NATCO Public School'), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Student name'),
      'Test Student Zzz',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // The new student sorts alphabetically among 100 seeded students, so
    // it need not land on the first (unscrolled) page — search narrows the
    // list down to it directly, which is what a real user would do too.
    await tester.enterText(find.byType(TextField).first, 'Test Student Zzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Test Student Zzz'), findsOneWidget);
  });

  testWidgets('a duplicate student is rejected with a named reason', (
    WidgetTester tester,
  ) async {
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
    );
    await signInAs(tester, container, UserRole.superAdmin);

    await tester.tap(find.text('Schools and hierarchy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karnataka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bengaluru Urban'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whitefield'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NATCO Public School'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View students'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Student name'),
      'Duplicate Test Student',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Duplicate Test Student',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ListTile, 'Duplicate Test Student'),
      findsOneWidget,
    );

    // Same name, same defaulted grade/section/dob (none set): a genuine
    // collision.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Student name'),
      'Duplicate Test Student',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already enrolled'), findsOneWidget);
  });

  testWidgets('CSV import reports what was created and rejected', (
    WidgetTester tester,
  ) async {
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[testAccount(UserRole.superAdmin)],
    );
    await signInAs(tester, container, UserRole.superAdmin);

    await tester.tap(find.text('Schools and hierarchy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Karnataka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bengaluru Urban'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whitefield'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NATCO Public School'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View students'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.upload_file_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).last,
      'studentName,grade,section\n'
      'Fresh Import Student,5,A\n'
      ',5,A\n',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 of 2'), findsOneWidget);
    expect(find.textContaining('student name is missing'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Fresh Import Student',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ListTile, 'Fresh Import Student'),
      findsOneWidget,
    );
  });
}
