/// Tests for [InMemoryStudentDataSource]: dedupe rejection, scope
/// filtering (including grade-section narrowing), and update rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/data/service/in_memory_student_data_source.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

void main() {
  final DateTime t0 = DateTime.utc(2026, 1, 1);

  Student student(
    String id, {
    String name = 'Ravi Kumar',
    String grade = '5',
    String section = 'A',
    String schoolId = 'sch1',
    String dedupeKey = 'dk1',
  }) => Student(
    studentId: id,
    studentName: name,
    gender: Gender.male,
    grade: grade,
    section: section,
    mediumOfInstruction: 'English',
    language: 'English',
    schoolId: schoolId,
    clusterId: 'cl1',
    districtId: 'di1',
    stateId: 'st1',
    activeStatus: true,
    dedupeKey: dedupeKey,
    createdAt: t0,
    updatedAt: t0,
  );

  group('createStudent', () {
    test('rejects a second student with the same dedupe key', () async {
      final InMemoryStudentDataSource source = InMemoryStudentDataSource(
        students: <Student>[student('stu1', dedupeKey: 'dk1')],
      );
      final Result<Student> result = await source.createStudent(
        student('stu2', dedupeKey: 'dk1'),
      );
      expect(result.isFailure, isTrue);
      final Failure failure = result.failureOrNull!;
      expect(failure, isA<DuplicateFailure>());
      expect((failure as DuplicateFailure).entityId, 'stu1');
    });

    test('accepts a genuinely new student', () async {
      final InMemoryStudentDataSource source = InMemoryStudentDataSource();
      final Result<Student> result = await source.createStudent(
        student('stu1', dedupeKey: 'dk1'),
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('updateStudent', () {
    test('refuses a change to dedupeKey', () async {
      final InMemoryStudentDataSource source = InMemoryStudentDataSource(
        students: <Student>[student('stu1', dedupeKey: 'dk1')],
      );
      final Result<Student> result = await source.updateStudent(
        student('stu1', dedupeKey: 'dk2'),
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('allows any other field to change', () async {
      final InMemoryStudentDataSource source = InMemoryStudentDataSource(
        students: <Student>[student('stu1', name: 'Ravi Kumar')],
      );
      final Result<Student> result = await source.updateStudent(
        student('stu1').copyWith(studentName: 'Ravi K.'),
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull?.studentName, 'Ravi K.');
    });
  });

  group('listStudents', () {
    test('a teacher scoped to one grade-section cannot see another section '
        'in the same school', () async {
      final InMemoryStudentDataSource source = InMemoryStudentDataSource(
        students: <Student>[
          student('stu1', section: 'A'),
          student('stu2', section: 'B'),
        ],
      );
      final Result<Page<Student>> result = await source.listStudents(
        scope: AccessScope.singleSchool(
          'sch1',
          gradeSections: <GradeSection>{
            const GradeSection(grade: '5', section: 'A'),
          },
        ),
      );
      expect(
        result.valueOrNull!.items.map((Student s) => s.studentId),
        <String>['stu1'],
      );
    });

    test('an optional schoolId filter narrows within scope', () async {
      final InMemoryStudentDataSource source = InMemoryStudentDataSource(
        students: <Student>[
          student('stu1', schoolId: 'sch1'),
          student('stu2', schoolId: 'sch2', dedupeKey: 'dk2'),
        ],
      );
      final Result<Page<Student>> result = await source.listStudents(
        scope: const AccessScope.global(),
        schoolId: 'sch2',
      );
      expect(
        result.valueOrNull!.items.map((Student s) => s.studentId),
        <String>['stu2'],
      );
    });
  });

  group('existingDedupeKeys', () {
    test('reports only the keys that already exist', () async {
      final InMemoryStudentDataSource source = InMemoryStudentDataSource(
        students: <Student>[student('stu1', dedupeKey: 'dk1')],
      );
      final Result<Set<String>> result = await source.existingDedupeKeys(
        <String>{'dk1', 'dk2'},
      );
      expect(result.valueOrNull, <String>{'dk1'});
    });
  });
}
