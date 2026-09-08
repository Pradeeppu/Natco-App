/// Parses CSV text into validated draft student rows.
///
/// Deliberately pure and persistence-free: it never calls a repository, never
/// checks for duplicates, and never decides whether a row is *importable*
/// (that requires knowing what already exists). It only decides whether a row
/// is *readable* — parseable into a row with the required fields present.
/// Duplicate checking happens afterward, in the repository, which is what
/// makes both halves independently testable.
///
/// Expected header row (case-insensitive, order-independent):
/// `studentName, grade, section, gender, dateOfBirth, mediumOfInstruction,
/// language, electiveSubject, externalStudentCode`. Only the first three are
/// required.
library;

import 'package:csv/csv.dart';
import 'package:natco_app/features/students/domain/entity/student_import_report.dart';

/// The result of parsing, before anything is persisted.
final class StudentCsvParseResult {
  const StudentCsvParseResult({required this.rows, required this.errors});

  final List<StudentImportRow> rows;
  final List<StudentImportParseError> errors;

  /// True when the file had no header, or the header named none of the
  /// required columns — the parse produced nothing worth reporting row by
  /// row, and the caller should show one message rather than a wall of
  /// per-row errors.
  bool get isUnreadable => rows.isEmpty && errors.length <= 1;
}

const List<String> _requiredColumns = <String>['studentname', 'grade', 'section'];

final class StudentCsvImporter {
  const StudentCsvImporter();

  StudentCsvParseResult parse(String csvText) {
    final List<List<Object?>> table = Csv(
      dynamicTyping: false,
    ).decode(csvText);

    if (table.isEmpty) {
      return const StudentCsvParseResult(
        rows: <StudentImportRow>[],
        errors: <StudentImportParseError>[
          StudentImportParseError(rowNumber: 1, reason: 'The file is empty.'),
        ],
      );
    }

    final List<String> header = table.first
        .map((Object? cell) => cell.toString().trim().toLowerCase())
        .toList(growable: false);
    final Map<String, int> columnIndex = <String, int>{
      for (int i = 0; i < header.length; i++) header[i]: i,
    };

    final List<String> missing = _requiredColumns
        .where((String c) => !columnIndex.containsKey(c))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      return StudentCsvParseResult(
        rows: const <StudentImportRow>[],
        errors: <StudentImportParseError>[
          StudentImportParseError(
            rowNumber: 1,
            reason:
                'Missing required column${missing.length > 1 ? 's' : ''}: '
                '${missing.join(', ')}.',
          ),
        ],
      );
    }

    final List<StudentImportRow> rows = <StudentImportRow>[];
    final List<StudentImportParseError> errors = <StudentImportParseError>[];

    for (int i = 1; i < table.length; i++) {
      final int rowNumber = i + 1; // 1-based, header counted as row 1.
      final List<Object?> raw = table[i];
      if (raw.every((Object? cell) => cell.toString().trim().isEmpty)) {
        continue; // a blank line is not a row worth reporting on
      }

      String? cell(String column) {
        final int? index = columnIndex[column];
        if (index == null || index >= raw.length) {
          return null;
        }
        final String value = raw[index].toString().trim();
        return value.isEmpty ? null : value;
      }

      final String? studentName = cell('studentname');
      final String? grade = cell('grade');
      final String? section = cell('section');

      final List<String> rowErrors = <String>[
        if (studentName == null) 'student name is missing',
        if (grade == null) 'grade is missing',
        if (section == null) 'section is missing',
      ];
      if (rowErrors.isNotEmpty) {
        errors.add(
          StudentImportParseError(
            rowNumber: rowNumber,
            reason: rowErrors.join('; '),
          ),
        );
        continue;
      }

      final String? dobText = cell('dateofbirth');
      final DateTime? parsedDob = dobText == null ? null : DateTime.tryParse(dobText);
      // Reconstructed as a UTC calendar date from its components, not via
      // `.toUtc()`: a date of birth is a calendar date, not an instant, and
      // naively converting a local-midnight parse to UTC would shift it to
      // the wrong day for any timezone ahead of UTC.
      final DateTime? dob = parsedDob == null
          ? null
          : DateTime.utc(parsedDob.year, parsedDob.month, parsedDob.day);
      if (dobText != null && dob == null) {
        errors.add(
          StudentImportParseError(
            rowNumber: rowNumber,
            reason: 'date of birth "$dobText" is not a valid date '
                '(use YYYY-MM-DD)',
          ),
        );
        continue;
      }

      rows.add(
        StudentImportRow(
          rowNumber: rowNumber,
          studentName: studentName!,
          grade: grade!,
          section: section!,
          gender: cell('gender'),
          dateOfBirth: dob,
          mediumOfInstruction: cell('mediumofinstruction'),
          language: cell('language'),
          electiveSubject: cell('electivesubject'),
          externalStudentCode: cell('externalstudentcode'),
        ),
      );
    }

    return StudentCsvParseResult(rows: rows, errors: errors);
  }
}
