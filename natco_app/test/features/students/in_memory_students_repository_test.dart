/// Scope-isolation and pagination tests for [InMemoryStudentsRepository].
///
/// Two things the Phase 2 exit criteria call out specifically
/// (docs/08-mvp-implementation-plan.md): a duplicate student is rejected with
/// a named reason (covered in depth by the CSV importer and widget smoke
/// tests), and a 2,000-student school scrolls rather than loading every row.
/// This file covers the second directly, plus scope isolation between
/// schools that the smoke tests don't exercise at the repository level.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

void main() {
  late InMemorySchoolsRepository schoolsRepo;
  late InMemoryStudentsRepository studentsRepo;
  const IdGenerator idGenerator = UuidIdGenerator();
  final Clock clock = FixedClock(DateTime.utc(2026, 9, 8));

  School seedSchool(String name, String code) {
    final DateTime now = clock.nowUtc();
    final GeoNode state = GeoNode(
      id: idGenerator.newId(),
      level: HierarchyLevel.state,
      name: 'State',
      code: 'ST',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    schoolsRepo.seedState(state);
    final GeoNode district = GeoNode(
      id: idGenerator.newId(),
      level: HierarchyLevel.district,
      name: 'District',
      code: 'DI',
      isActive: true,
      createdAt: now,
      updatedAt: now,
      parentId: state.id,
      stateId: state.id,
    );
    schoolsRepo.seedDistrict(district);
    final GeoNode cluster = GeoNode(
      id: idGenerator.newId(),
      level: HierarchyLevel.cluster,
      name: 'Cluster',
      code: 'CL',
      isActive: true,
      createdAt: now,
      updatedAt: now,
      parentId: district.id,
      stateId: state.id,
      districtId: district.id,
    );
    schoolsRepo.seedCluster(cluster);
    final School school = School(
      schoolId: idGenerator.newId(),
      schoolName: name,
      schoolCode: code,
      clusterId: cluster.id,
      districtId: district.id,
      stateId: state.id,
      grades: const <String>['5'],
      mediumsOfInstruction: const <String>['English'],
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    schoolsRepo.seedSchool(school);
    return school;
  }

  setUp(() {
    schoolsRepo = InMemorySchoolsRepository(idGenerator: idGenerator, clock: clock);
    studentsRepo = InMemoryStudentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schoolsRepo,
    );
  });

  group('scope isolation', () {
    test('a school-scoped user cannot list another school\'s students', () async {
      final School schoolA = seedSchool('School A', 'A1');
      final School schoolB = seedSchool('School B', 'B1');
      await studentsRepo.createStudent(
        schoolId: schoolA.schoolId,
        studentName: 'Student In A',
        gender: Gender.male,
        grade: '5',
        section: 'A',
        mediumOfInstruction: 'English',
        language: 'English',
      );
      await studentsRepo.createStudent(
        schoolId: schoolB.schoolId,
        studentName: 'Student In B',
        gender: Gender.female,
        grade: '5',
        section: 'A',
        mediumOfInstruction: 'English',
        language: 'English',
      );

      final AccessScope scopedToA = AccessScope.singleSchool(schoolA.schoolId);
      final pageForA = await studentsRepo.listStudents(
        scope: scopedToA,
        schoolId: schoolA.schoolId,
      );
      expect(pageForA.valueOrNull!.items, hasLength(1));
      expect(pageForA.valueOrNull!.items.single.studentName, 'Student In A');

      // Asking that same scope for school B's roster returns nothing, not an
      // error and not school A's data — the scope check is per-record, not
      // "the caller is trusted once they name any schoolId".
      final pageForBUnderScopeA = await studentsRepo.listStudents(
        scope: scopedToA,
        schoolId: schoolB.schoolId,
      );
      expect(pageForBUnderScopeA.valueOrNull!.items, isEmpty);
    });

    test('getStudent denies a student outside the caller\'s scope', () async {
      final School schoolA = seedSchool('School A', 'A1');
      final School schoolB = seedSchool('School B', 'B1');
      final created = await studentsRepo.createStudent(
        schoolId: schoolB.schoolId,
        studentName: 'Student In B',
        gender: Gender.female,
        grade: '5',
        section: 'A',
        mediumOfInstruction: 'English',
        language: 'English',
      );
      final Student student = created.valueOrNull!;

      final result = await studentsRepo.getStudent(
        student.studentId,
        scope: AccessScope.singleSchool(schoolA.schoolId),
      );
      expect(result.failureOrNull, isNotNull);
    });

    test('a teacher scope narrowed to one grade-section only sees that roster', () async {
      final School school = seedSchool('School A', 'A1');
      await studentsRepo.createStudent(
        schoolId: school.schoolId,
        studentName: 'Grade 5A Student',
        gender: Gender.male,
        grade: '5',
        section: 'A',
        mediumOfInstruction: 'English',
        language: 'English',
      );
      await studentsRepo.createStudent(
        schoolId: school.schoolId,
        studentName: 'Grade 5B Student',
        gender: Gender.male,
        grade: '5',
        section: 'B',
        mediumOfInstruction: 'English',
        language: 'English',
      );

      final AccessScope teacherScope = AccessScope.singleSchool(
        school.schoolId,
        gradeSections: <GradeSection>{
          const GradeSection(grade: '5', section: 'A'),
        },
      );
      final page = await studentsRepo.listStudents(
        scope: teacherScope,
        schoolId: school.schoolId,
      );
      expect(page.valueOrNull!.items, hasLength(1));
      expect(page.valueOrNull!.items.single.studentName, 'Grade 5A Student');
    });
  });

  group('pagination at scale', () {
    test('a 2,000-student school pages without ever returning them all at once', () async {
      final School school = seedSchool('Big School', 'BIG1');
      final DateTime firstBirthDate = DateTime.utc(2010, 1, 1);
      for (int i = 0; i < 2000; i++) {
        studentsRepo.seedStudent(
          schoolId: school.schoolId,
          studentName: 'Student ${i.toString().padLeft(4, '0')}',
          gender: i.isEven ? Gender.male : Gender.female,
          grade: '5',
          section: 'A',
          mediumOfInstruction: 'English',
          language: 'English',
          dateOfBirth: firstBirthDate.add(Duration(days: i)),
        );
      }

      const AccessScope scope = AccessScope.global();
      final Set<String> seenIds = <String>{};
      String? cursor;
      int pageCount = 0;
      do {
        final result = await studentsRepo.listStudents(
          scope: scope,
          schoolId: school.schoolId,
          request: PageRequest(cursor: cursor),
        );
        final page = result.valueOrNull!;
        // The default page size, never the whole roster in one response.
        expect(page.items.length, lessThanOrEqualTo(kDefaultPageSize));
        seenIds.addAll(page.items.map((Student s) => s.studentId));
        cursor = page.nextCursor;
        pageCount++;
      } while (cursor != null);

      expect(seenIds, hasLength(2000));
      expect(pageCount, 2000 ~/ kDefaultPageSize);
    });

    test('the first page alone never contains the whole roster', () async {
      final School school = seedSchool('Big School', 'BIG2');
      final DateTime firstBirthDate = DateTime.utc(2010, 1, 1);
      for (int i = 0; i < 2000; i++) {
        studentsRepo.seedStudent(
          schoolId: school.schoolId,
          studentName: 'Student ${i.toString().padLeft(4, '0')}',
          gender: Gender.male,
          grade: '5',
          section: 'A',
          mediumOfInstruction: 'English',
          language: 'English',
          dateOfBirth: firstBirthDate.add(Duration(days: i)),
        );
      }

      final result = await studentsRepo.listStudents(
        scope: const AccessScope.global(),
        schoolId: school.schoolId,
      );
      final page = result.valueOrNull!;
      expect(page.items, hasLength(kDefaultPageSize));
      expect(page.hasMore, isTrue);
    });
  });
}
