/// Tests for the CSV importer.
///
/// This layer only decides whether a row is *readable*. It never touches a
/// repository and never decides whether a row is a duplicate — that split is
/// what makes both halves testable independently (see
/// `student_csv_importer.dart`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/students/domain/entity/student_import_report.dart';
import 'package:natco_app/features/students/domain/service/student_csv_importer.dart';

void main() {
  const StudentCsvImporter importer = StudentCsvImporter();

  group('happy path', () {
    test('parses every required and optional column', () {
      const String csv =
          'studentName,grade,section,gender,dateOfBirth,mediumOfInstruction,'
          'language,electiveSubject,externalStudentCode\n'
          'Ravi Kumar,5,A,MALE,2015-04-02,English,English,Art,ST00123\n';

      final StudentCsvParseResult result = importer.parse(csv);

      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(1));
      final StudentImportRow row = result.rows.single;
      expect(row.rowNumber, 2);
      expect(row.studentName, 'Ravi Kumar');
      expect(row.grade, '5');
      expect(row.section, 'A');
      expect(row.gender, 'MALE');
      expect(row.dateOfBirth, DateTime.utc(2015, 4, 2));
      expect(row.mediumOfInstruction, 'English');
      expect(row.electiveSubject, 'Art');
      expect(row.externalStudentCode, 'ST00123');
    });

    test('accepts only the required columns', () {
      const String csv = 'studentName,grade,section\nMeera Nair,5,B\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.single.studentName, 'Meera Nair');
    });

    test('column order does not matter', () {
      const String csv = 'section,studentName,grade\nB,Meera Nair,5\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows.single.studentName, 'Meera Nair');
      expect(result.rows.single.grade, '5');
      expect(result.rows.single.section, 'B');
    });

    test('columns are matched case-insensitively', () {
      const String csv = 'STUDENTNAME,Grade,SeCtIoN\nMeera Nair,5,B\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows, hasLength(1));
    });

    test('parses several rows, numbering from the header', () {
      const String csv =
          'studentName,grade,section\n'
          'Ravi Kumar,5,A\n'
          'Meera Nair,5,B\n'
          'Suresh Babu,6,A\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows.map((StudentImportRow r) => r.rowNumber), <int>[
        2,
        3,
        4,
      ]);
    });

    test('skips a blank line without reporting it as an error', () {
      const String csv = 'studentName,grade,section\nRavi Kumar,5,A\n\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows, hasLength(1));
      expect(result.errors, isEmpty);
    });

    test('treats a row of only empty fields as blank, not an error', () {
      // Trailing padding in a spreadsheet export ("a,,\n" with nothing
      // meaningful entered) is noise, not a row a human needs to fix.
      const String csv = 'studentName,grade,section\n,,\nMeera Nair,5,B\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows, hasLength(1));
      expect(result.errors, isEmpty);
    });
  });

  group('missing required columns', () {
    test('reports a single file-level error naming what is missing', () {
      const String csv = 'studentName,grade\nRavi Kumar,5\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.reason, contains('section'));
      expect(result.isUnreadable, isTrue);
    });

    test('names every missing column, not just the first', () {
      const String csv = 'gender\nMALE\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.errors.single.reason, contains('studentname'));
      expect(result.errors.single.reason, contains('grade'));
      expect(result.errors.single.reason, contains('section'));
    });
  });

  group('per-row validation', () {
    test('rejects a row missing a required field, by name', () {
      const String csv =
          'studentName,grade,section\n'
          ',5,A\n'
          'Meera Nair,5,B\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows, hasLength(1));
      expect(result.rows.single.studentName, 'Meera Nair');
      expect(result.errors, hasLength(1));
      expect(result.errors.single.rowNumber, 2);
      expect(result.errors.single.reason, contains('student name'));
    });

    test('reports every missing field on one row together', () {
      // A row with at least one value present, so the decoder does not treat
      // it as a blank line (an all-empty row is indistinguishable from
      // padding and is silently skipped — see the empty-input group).
      const String csv = 'studentName,grade,section\nRavi,,\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.errors.single.reason, contains('grade'));
      expect(result.errors.single.reason, contains('section'));
      expect(result.errors.single.reason, isNot(contains('student name')));
    });

    test('rejects an unparseable date of birth', () {
      const String csv =
          'studentName,grade,section,dateOfBirth\n'
          'Ravi Kumar,5,A,02-04-2015\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors.single.reason, contains('date of birth'));
      expect(result.errors.single.reason, contains('02-04-2015'));
    });

    test('one bad row does not stop the rest from importing', () {
      const String csv =
          'studentName,grade,section\n'
          ',5,A\n'
          'Meera Nair,5,B\n'
          'Suresh Babu,6,A\n';
      final StudentCsvParseResult result = importer.parse(csv);
      expect(result.rows, hasLength(2));
      expect(result.errors, hasLength(1));
    });
  });

  group('empty input', () {
    test('an empty file is reported as unreadable, not as zero rows', () {
      final StudentCsvParseResult result = importer.parse('');
      expect(result.rows, isEmpty);
      expect(result.errors, hasLength(1));
      expect(result.isUnreadable, isTrue);
    });

    test('a header with no data rows imports nothing and errors nothing', () {
      final StudentCsvParseResult result = importer.parse(
        'studentName,grade,section\n',
      );
      expect(result.rows, isEmpty);
      expect(result.errors, isEmpty);
    });
  });
}
