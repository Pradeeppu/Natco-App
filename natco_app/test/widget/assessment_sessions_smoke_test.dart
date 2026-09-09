/// Smoke test driving the real session-lifecycle screens with connectivity
/// forced offline throughout — the "airplane-mode run completes end to end"
/// exit criterion (docs/08-mvp-implementation-plan.md), exercised through the
/// real app wiring rather than asserted by code inspection.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/data/local/demo_assessment_data.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';
import 'package:riverpod/misc.dart' show Override;

import 'test_harness.dart';

void main() {
  testWidgets(
    'a session downloads, starts, runs and completes with connectivity offline the whole time',
    (WidgetTester tester) async {
      // Seeded directly, outside any container — the robust pattern the
      // Phase 2 "teacher scoped to one school" test settled on: a school-
      // scoped teacher's scope has to name a school that actually exists,
      // and seeding once here (rather than letting two containers each seed
      // their own copy) guarantees it does.
      const IdGenerator idGenerator = UuidIdGenerator();
      final Clock clock = FixedClock(DateTime.utc(2026, 9, 10, 9));
      final InMemorySchoolsRepository schools = InMemorySchoolsRepository(
        idGenerator: idGenerator,
        clock: clock,
      );
      final InMemoryStudentsRepository students = InMemoryStudentsRepository(
        idGenerator: idGenerator,
        clock: clock,
        schools: schools,
      );
      final InMemoryAssessmentsRepository assessments =
          InMemoryAssessmentsRepository(
            idGenerator: idGenerator,
            clock: clock,
            schools: schools,
          );
      final List<School> seededSchools = seedDemoMasterData(
        schools: schools,
        students: students,
        idGenerator: idGenerator,
        clock: clock,
      );
      seedDemoAssessmentData(
        assessments: assessments,
        seededSchools: seededSchools,
        idGenerator: idGenerator,
        clock: clock,
      );
      final String schoolId = seededSchools.first.schoolId;

      final DemoAccount teacher = DemoAccount(
        user: testAccount(UserRole.pstTeacher).user
            .copyWith(scope: AccessScope.singleSchool(schoolId)),
        password: kTestPassword,
      );
      final container = await pumpApp(
        tester,
        accounts: <DemoAccount>[teacher],
        // Offline for the entire test: nothing in the flow below may depend
        // on a connection once the prerequisites download completes.
        connection: ConnectionStatus.offline,
        extraOverrides: <Override>[
          schoolsRepositoryProvider.overrideWithValue(schools),
          studentsRepositoryProvider.overrideWithValue(students),
          assessmentsRepositoryProvider.overrideWithValue(assessments),
        ],
      );
      await signInAs(tester, container, UserRole.pstTeacher);

      expect(find.textContaining('Offline'), findsWidgets);

      await scrollTo(tester, find.text('Start or continue assessment'));
      await tester.tap(find.text('Start or continue assessment'));
      await tester.pumpAndSettle();

      expect(find.text('Start a new session'), findsOneWidget);
      expect(find.textContaining('Term 1 English Assessment'), findsNothing);
      // The assignment card shows grade + sections, not the assessment name.
      expect(find.textContaining('Grade 5'), findsOneWidget);
      expect(find.text('Download for offline'), findsOneWidget);

      await tester.tap(find.text('Download for offline'));
      await tester.pumpAndSettle();

      expect(find.text('Download for offline'), findsNothing);
      expect(find.text('Start Section A'), findsOneWidget);
      expect(find.text('Start Section B'), findsOneWidget);

      await tester.tap(find.text('Start Section A'));
      await tester.pumpAndSettle();

      // Opening a freshly-started session auto-advances it into IN_PROGRESS —
      // there is no separate "begin capturing" action until Phase 5. The
      // live session screen is deliberately outside the navigation shell
      // (so a teacher cannot wander off mid-session), which is also where
      // the offline banner lives — there is nothing further here that could
      // depend on a connection, which is the point: reaching IN_PROGRESS and
      // then COMPLETED below never touches a network-backed repository.
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Grade 5 · Section A'), findsOneWidget);

      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End session').last);
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);
    },
  );

  testWidgets('a second session cannot be started for an un-downloaded assignment', (
    WidgetTester tester,
  ) async {
    const IdGenerator idGenerator = UuidIdGenerator();
    final Clock clock = FixedClock(DateTime.utc(2026, 9, 10, 9));
    final InMemorySchoolsRepository schools = InMemorySchoolsRepository(
      idGenerator: idGenerator,
      clock: clock,
    );
    final InMemoryStudentsRepository students = InMemoryStudentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    final InMemoryAssessmentsRepository assessments =
        InMemoryAssessmentsRepository(
          idGenerator: idGenerator,
          clock: clock,
          schools: schools,
        );
    final List<School> seededSchools = seedDemoMasterData(
      schools: schools,
      students: students,
      idGenerator: idGenerator,
      clock: clock,
    );
    seedDemoAssessmentData(
      assessments: assessments,
      seededSchools: seededSchools,
      idGenerator: idGenerator,
      clock: clock,
    );
    final String schoolId = seededSchools.first.schoolId;

    final DemoAccount teacher = DemoAccount(
      user: testAccount(UserRole.pstTeacher).user
          .copyWith(scope: AccessScope.singleSchool(schoolId)),
      password: kTestPassword,
    );
    final container = await pumpApp(
      tester,
      accounts: <DemoAccount>[teacher],
      extraOverrides: <Override>[
        schoolsRepositoryProvider.overrideWithValue(schools),
        studentsRepositoryProvider.overrideWithValue(students),
        assessmentsRepositoryProvider.overrideWithValue(assessments),
      ],
    );
    await signInAs(tester, container, UserRole.pstTeacher);

    await scrollTo(tester, find.text('Start or continue assessment'));
    await tester.tap(find.text('Start or continue assessment'));
    await tester.pumpAndSettle();

    // No "Start Section" button exists until the assignment is downloaded.
    expect(find.textContaining('Start Section'), findsNothing);
    expect(find.text('Download for offline'), findsOneWidget);
  });
}
