/// Tests for the demo dataset generator.
///
/// This asserts the exact counts requirement section 53 specifies, and that
/// seeding goes through the ordinary create/dedupe path rather than bypassing
/// it — a seed dataset with an internal collision would fail loudly here
/// rather than silently in someone's demo.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';

void main() {
  late InMemorySchoolsRepository schools;
  late InMemoryStudentsRepository students;

  setUp(() {
    const IdGenerator idGenerator = UuidIdGenerator();
    final Clock clock = FixedClock(DateTime.utc(2026, 9, 8));
    schools = InMemorySchoolsRepository(idGenerator: idGenerator, clock: clock);
    students = InMemoryStudentsRepository(
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
  });

  test('seeds exactly the counts requirement section 53 specifies', () async {
    const AccessScope global = AccessScope.global();
    final statesPage = await schools.listStates(
      scope: global,
      request: const PageRequest(limit: 100),
    );
    expect(statesPage.valueOrNull!.items, hasLength(1));

    final String stateId = statesPage.valueOrNull!.items.single.id;
    final districtsPage = await schools.listDistricts(
      scope: global,
      stateId: stateId,
      request: const PageRequest(limit: 100),
    );
    expect(districtsPage.valueOrNull!.items, hasLength(2));

    int clusterCount = 0;
    for (final district in districtsPage.valueOrNull!.items) {
      final clustersPage = await schools.listClusters(
        scope: global,
        districtId: district.id,
        request: const PageRequest(limit: 100),
      );
      clusterCount += clustersPage.valueOrNull!.items.length;
    }
    expect(clusterCount, 3);

    final schoolsPage = await schools.listSchools(
      scope: global,
      request: const PageRequest(limit: 100),
    );
    expect(schoolsPage.valueOrNull!.items, hasLength(5));

    int studentCount = 0;
    for (final school in schoolsPage.valueOrNull!.items) {
      final page = await students.listStudents(
        scope: global,
        schoolId: school.schoolId,
        request: const PageRequest(limit: 200),
      );
      studentCount += page.valueOrNull!.items.length;
    }
    expect(studentCount, 100);
  });

  test('every seeded student resolves ancestry from its real school', () async {
    final schoolsPage = await schools.listSchools(
      scope: const AccessScope.global(),
      request: const PageRequest(limit: 100),
    );
    for (final school in schoolsPage.valueOrNull!.items) {
      final page = await students.listStudents(
        scope: const AccessScope.global(),
        schoolId: school.schoolId,
        request: const PageRequest(limit: 200),
      );
      for (final student in page.valueOrNull!.items) {
        expect(student.clusterId, school.clusterId);
        expect(student.districtId, school.districtId);
        expect(student.stateId, school.stateId);
      }
    }
  });

  test('no real student data appears in the demo dataset', () async {
    // Requirement section 53: names here are placeholders, not real students.
    final schoolsPage = await schools.listSchools(
      scope: const AccessScope.global(),
      request: const PageRequest(limit: 100),
    );
    for (final school in schoolsPage.valueOrNull!.items) {
      final page = await students.listStudents(
        scope: const AccessScope.global(),
        schoolId: school.schoolId,
        request: const PageRequest(limit: 200),
      );
      for (final student in page.valueOrNull!.items) {
        expect(student.externalStudentCode, isNull);
      }
    }
  });
}
