/// Tests for [InMemorySchoolDataSource]: scope filtering, search, pagination
/// and uniqueness on create.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/service/in_memory_school_data_source.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

void main() {
  final DateTime t0 = DateTime.utc(2026, 1, 1);

  District district(String id, String stateId) => District(
    districtId: id,
    districtName: id,
    districtCode: id,
    stateId: stateId,
    isActive: true,
    createdAt: t0,
    updatedAt: t0,
  );

  Cluster cluster(String id, String districtId, String stateId) => Cluster(
    clusterId: id,
    clusterName: id,
    clusterCode: id,
    districtId: districtId,
    stateId: stateId,
    isActive: true,
    createdAt: t0,
    updatedAt: t0,
  );

  School school(
    String id,
    String name, {
    String clusterId = 'cl1',
    String districtId = 'di1',
    String stateId = 'st1',
  }) => School(
    schoolId: id,
    schoolName: name,
    schoolCode: id.toUpperCase(),
    clusterId: clusterId,
    districtId: districtId,
    stateId: stateId,
    grades: const <String>['5'],
    mediumsOfInstruction: const <String>['English'],
    isActive: true,
    createdAt: t0,
    updatedAt: t0,
  );

  group('listSchools', () {
    test('a global scope sees every school, paginated', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        schools: List<School>.generate(
          5,
          (int i) => school('sch$i', 'School $i'),
        ),
      );
      final Result<Page<School>> firstPage = await source.listSchools(
        scope: const AccessScope.global(),
        pageSize: 2,
      );
      final Page<School> page1 = firstPage.valueOrNull!;
      expect(page1.items, hasLength(2));
      expect(page1.hasMore, isTrue);

      final Result<Page<School>> secondPage = await source.listSchools(
        scope: const AccessScope.global(),
        cursor: page1.nextCursor,
        pageSize: 2,
      );
      expect(secondPage.valueOrNull!.items, hasLength(2));
    });

    test('a school-scoped user sees only their explicit schools', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        schools: <School>[
          school('sch1', 'A'),
          school('sch2', 'B'),
          school('sch3', 'C'),
        ],
      );
      final Result<Page<School>> result = await source.listSchools(
        scope: AccessScope.singleSchool('sch2'),
      );
      expect(
        result.valueOrNull!.items.map((School s) => s.schoolId),
        <String>['sch2'],
      );
    });

    test('a cluster-scoped user cannot see a neighbouring cluster', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        schools: <School>[
          school('sch1', 'A', clusterId: 'cl1'),
          school('sch2', 'B', clusterId: 'cl2'),
        ],
      );
      final Result<Page<School>> result = await source.listSchools(
        scope: const AccessScope(
          level: ScopeLevel.cluster,
          clusterIds: <String>{'cl1'},
        ),
      );
      expect(
        result.valueOrNull!.items.map((School s) => s.schoolId),
        <String>['sch1'],
      );
    });

    test('search matches name or code, case-insensitively', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        schools: <School>[school('sch1', 'Riverside Primary')],
      );
      final Result<Page<School>> result = await source.listSchools(
        scope: const AccessScope.global(),
        query: 'riverside',
      );
      expect(result.valueOrNull!.items, hasLength(1));
    });

    test('an empty scope reaches nothing', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        schools: <School>[school('sch1', 'A')],
      );
      final Result<Page<School>> result = await source.listSchools(
        scope: const AccessScope(level: ScopeLevel.school),
      );
      expect(result.valueOrNull!.items, isEmpty);
    });
  });

  group('listDistricts / listClusters', () {
    test('with no parent id, a district-scoped user sees only their own', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        districts: <District>[district('di1', 'st1'), district('di2', 'st1')],
      );
      final Result<Page<District>> result = await source.listDistricts(
        scope: const AccessScope(
          level: ScopeLevel.district,
          districtIds: <String>{'di1'},
        ),
      );
      expect(
        result.valueOrNull!.items.map((District d) => d.districtId),
        <String>['di1'],
      );
    });

    test('with a parent id, results are also scope-checked', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        clusters: <Cluster>[
          cluster('cl1', 'di1', 'st1'),
          cluster('cl2', 'di1', 'st1'),
        ],
      );
      final Result<Page<Cluster>> result = await source.listClusters(
        scope: const AccessScope(
          level: ScopeLevel.cluster,
          clusterIds: <String>{'cl1'},
        ),
        districtId: 'di1',
      );
      expect(
        result.valueOrNull!.items.map((Cluster c) => c.clusterId),
        <String>['cl1'],
      );
    });
  });

  group('createSchool', () {
    test('rejects a duplicate school code with a named reason', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource(
        schools: <School>[school('sch1', 'Original')],
      );
      final Result<School> result = await source.createSchool(
        school('sch2', 'Copycat').copyWith(schoolCode: 'SCH1'),
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<DuplicateFailure>());
    });

    test('accepts a genuinely new school', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource();
      final Result<School> result = await source.createSchool(
        school('sch1', 'New School'),
      );
      expect(result.isSuccess, isTrue);
      final Result<School> fetched = await source.getSchool('sch1');
      expect(fetched.valueOrNull?.schoolName, 'New School');
    });
  });

  group('getSchool', () {
    test('reports not found for an unknown id', () async {
      final InMemorySchoolDataSource source = InMemorySchoolDataSource();
      final Result<School> result = await source.getSchool('missing');
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });
}
