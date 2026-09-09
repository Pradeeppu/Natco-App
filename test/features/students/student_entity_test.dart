/// Round-trip and equality tests for [Student].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

void main() {
  final DateTime t0 = DateTime.utc(2026, 1, 1);
  final DateTime dob = DateTime.utc(2015, 4, 2);

  // A `DateTime? dateOfBirth` parameter defaulting to `dob` via `??` could
  // not express "no date of birth" at all, which is exactly what one of
  // these tests needs.
  Student build({bool withDateOfBirth = true}) => Student(
    studentId: 'stu1',
    studentName: 'Ravi Kumar',
    gender: Gender.male,
    dateOfBirth: withDateOfBirth ? dob : null,
    grade: '5',
    section: 'A',
    mediumOfInstruction: 'English',
    language: 'English',
    electiveSubject: 'Sanskrit',
    schoolId: 'sch1',
    clusterId: 'cl1',
    districtId: 'di1',
    stateId: 'st1',
    activeStatus: true,
    dedupeKey: 'dk1',
    createdAt: t0,
    updatedAt: t0,
  );

  group('round trip', () {
    test('every field survives toJson/tryFromJson', () {
      final Student original = build();
      final Student? decoded = Student.tryFromJson(original.toJson());
      expect(decoded, original);
    });

    test('a null date of birth round-trips as null', () {
      final Student original = build(withDateOfBirth: false);
      final Student? decoded = Student.tryFromJson(original.toJson());
      expect(decoded!.dateOfBirth, isNull);
    });

    test('rejects a document missing required fields', () {
      expect(Student.tryFromJson(<String, Object?>{}), isNull);
    });

    test('an unrecognised gender decodes to notSpecified rather than failing', () {
      final Map<String, Object?> json = build().toJson();
      json['gender'] = 'SOMETHING_A_FUTURE_BUILD_ADDED';
      expect(Student.tryFromJson(json)!.gender, Gender.notSpecified);
    });
  });

  group('copyWith', () {
    test('never changes identity fields', () {
      final Student original = build();
      final Student updated = original.copyWith(studentName: 'Ravi K.');
      expect(updated.studentId, original.studentId);
      expect(updated.schoolId, original.schoolId);
      expect(updated.dedupeKey, original.dedupeKey);
      expect(updated.studentName, 'Ravi K.');
    });
  });

  group('toString', () {
    test('never includes the student\'s name or date of birth', () {
      final String text = build().toString();
      expect(text, isNot(contains('Ravi')));
      expect(text, isNot(contains('2015')));
    });
  });
}
