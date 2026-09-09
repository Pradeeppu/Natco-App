/// Tests for [CsvStudentParser]: well-formed rows, missing columns, bad
/// dates, and blank lines.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/students/data/service/csv_student_parser.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

void main() {
  const CsvStudentParser parser = CsvStudentParser();
  const String header =
      'studentName,gender,dateOfBirth,grade,section,mediumOfInstruction,'
      'language,electiveSubject,externalStudentCode';

  test('parses a well-formed file with optional columns present', () {
    final CsvParseOutcome outcome = parser.parse(
      '$header\n'
      'Ravi Kumar,MALE,2015-04-02,5,A,English,English,Sanskrit,EX001\n'
      'Priya Rao,FEMALE,,5,B,English,English,,\n',
    );
    expect(outcome.errors, isEmpty);
    expect(outcome.rows, hasLength(2));
    expect(outcome.rows.first.draft.studentName, 'Ravi Kumar');
    expect(outcome.rows.first.draft.gender, Gender.male);
    expect(outcome.rows.first.draft.dateOfBirth, DateTime.utc(2015, 4, 2));
    expect(outcome.rows.last.draft.dateOfBirth, isNull);
    expect(outcome.rows.last.draft.electiveSubject, isNull);
  });

  test('parses a file with only the required columns', () {
    final CsvParseOutcome outcome = parser.parse(
      'studentName,grade,section,mediumOfInstruction,language\n'
      'Ravi Kumar,5,A,English,English\n',
    );
    expect(outcome.errors, isEmpty);
    expect(outcome.rows, hasLength(1));
    expect(outcome.rows.single.draft.gender, Gender.notSpecified);
  });

  test('rejects the whole file when a required column is missing', () {
    final CsvParseOutcome outcome = parser.parse(
      'studentName,grade,section,mediumOfInstruction\n'
      'Ravi Kumar,5,A,English\n',
    );
    expect(outcome.rows, isEmpty);
    expect(outcome.errors, hasLength(1));
    expect(outcome.errors.single.reason, contains('language'));
  });

  test('rejects a row missing a required value, keeping the rest', () {
    final CsvParseOutcome outcome = parser.parse(
      '$header\n'
      'Ravi Kumar,MALE,2015-04-02,5,A,English,English,,\n'
      ',MALE,2015-04-02,5,A,English,English,,\n'
      'Priya Rao,FEMALE,2015-05-01,5,B,English,English,,\n',
    );
    expect(outcome.rows, hasLength(2));
    expect(outcome.errors, hasLength(1));
    expect(outcome.errors.single.rowNumber, 2);
  });

  test('rejects a row with an unparseable date, keeping the rest', () {
    final CsvParseOutcome outcome = parser.parse(
      '$header\n'
      'Ravi Kumar,MALE,02-04-2015,5,A,English,English,,\n',
    );
    expect(outcome.rows, isEmpty);
    expect(outcome.errors, hasLength(1));
    expect(outcome.errors.single.reason, contains('YYYY-MM-DD'));
  });

  test('skips a trailing blank line without an error', () {
    final CsvParseOutcome outcome = parser.parse(
      'studentName,grade,section,mediumOfInstruction,language\n'
      'Ravi Kumar,5,A,English,English\n'
      '\n',
    );
    expect(outcome.rows, hasLength(1));
    expect(outcome.errors, isEmpty);
  });

  test('an empty file is one file-level error, not a crash', () {
    final CsvParseOutcome outcome = parser.parse('');
    expect(outcome.rows, isEmpty);
    expect(outcome.errors, hasLength(1));
  });

  test('column matching is case-insensitive', () {
    final CsvParseOutcome outcome = parser.parse(
      'STUDENTNAME,GRADE,SECTION,MEDIUMOFINSTRUCTION,LANGUAGE\n'
      'Ravi Kumar,5,A,English,English\n',
    );
    expect(outcome.errors, isEmpty);
    expect(outcome.rows, hasLength(1));
  });
}
