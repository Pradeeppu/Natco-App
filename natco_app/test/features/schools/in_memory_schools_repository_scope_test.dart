/// Scope-isolation tests for [InMemorySchoolsRepository].
///
/// The repository's own `_filtered` helper is what enforces
/// `AccessScope.covers` on every list call (docs/04-security-model.md) — this
/// used to be missing entirely (every list call returned unscoped results)
/// until it was caught and fixed during Phase 2. These tests exist so that
/// regression cannot slip back in unnoticed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
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
    // Karnataka > {Bengaluru Urban > {Whitefield, Koramangala},
    // Mysuru > {Mysuru North}}, 5 schools spread across the 3 clusters.
    seedDemoMasterData(
      schools: schools,
      students: students,
      idGenerator: idGenerator,
      clock: clock,
    );
  });

  Future<String> clusterIdNamed(String name) async {
    final statesPage = await schools.listStates(scope: const AccessScope.global());
    final stateId = statesPage.valueOrNull!.items.single.id;
    final districtsPage = await schools.listDistricts(
      scope: const AccessScope.global(),
      stateId: stateId,
    );
    for (final district in districtsPage.valueOrNull!.items) {
      final clustersPage = await schools.listClusters(
        scope: const AccessScope.global(),
        districtId: district.id,
      );
      for (final cluster in clustersPage.valueOrNull!.items) {
        if (cluster.name == name) {
          return cluster.id;
        }
      }
    }
    fail('no cluster named "$name" in the seeded dataset');
  }

  test('a cluster-scoped Supervisor only sees schools in their cluster', () async {
    final String whitefieldId = await clusterIdNamed('Whitefield');
    final AccessScope scope = AccessScope(
      level: ScopeLevel.cluster,
      clusterIds: <String>{whitefieldId},
    );

    final page = await schools.listSchools(scope: scope);
    final List<String> names = page.valueOrNull!.items
        .map((School s) => s.schoolName)
        .toList();

    // Whitefield holds exactly the first 2 seeded schools.
    expect(names, containsAll(<String>['NATCO Public School', 'Green Valley School']));
    expect(names, isNot(contains('St. Xavier\'s High School')));
    expect(names, isNot(contains('Sunrise Vidyalaya')));
    expect(names, isNot(contains('Lakeview School')));
  });

  test('listSchools with no clusterId filter still respects scope', () async {
    final String koramangalaId = await clusterIdNamed('Koramangala');
    final AccessScope scope = AccessScope(
      level: ScopeLevel.cluster,
      clusterIds: <String>{koramangalaId},
    );

    // No clusterId passed: the repository must not fall back to "every
    // school", only "every school this scope covers".
    final page = await schools.listSchools(scope: scope);
    expect(page.valueOrNull!.items, hasLength(1));
    expect(page.valueOrNull!.items.single.schoolName, "St. Xavier's High School");
  });

  test('a global scope sees every school regardless of cluster', () async {
    final page = await schools.listSchools(
      scope: const AccessScope.global(),
      request: const PageRequest(limit: 100),
    );
    expect(page.valueOrNull!.items, hasLength(5));
  });

  test('getSchool denies a school outside the caller\'s scope', () async {
    final String whitefieldId = await clusterIdNamed('Whitefield');
    final String koramangalaId = await clusterIdNamed('Koramangala');
    final AccessScope whitefieldScope = AccessScope(
      level: ScopeLevel.cluster,
      clusterIds: <String>{whitefieldId},
    );
    final koramangalaSchools = await schools.listSchools(
      scope: AccessScope(level: ScopeLevel.cluster, clusterIds: <String>{koramangalaId}),
    );
    final String outOfScopeSchoolId =
        koramangalaSchools.valueOrNull!.items.single.schoolId;

    final result = await schools.getSchool(
      outOfScopeSchoolId,
      scope: whitefieldScope,
    );
    expect(result.failureOrNull, isNotNull);
  });

  test('a school-scoped user\'s scope reaches only that one school', () async {
    final allSchools = await schools.listSchools(
      scope: const AccessScope.global(),
      request: const PageRequest(limit: 100),
    );
    final String targetSchoolId = allSchools.valueOrNull!.items.first.schoolId;
    final AccessScope scope = AccessScope.singleSchool(targetSchoolId);

    final page = await schools.listSchools(scope: scope);
    expect(page.valueOrNull!.items, hasLength(1));
    expect(page.valueOrNull!.items.single.schoolId, targetSchoolId);
  });
}
