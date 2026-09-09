/// Parses a student-import CSV into [StudentImportRow]s.
///
/// Pure Dart — no file access, no Firebase — so it is unit-testable without
/// a device or a picked file. Deciding *which* rows are duplicates happens
/// later, against the repository (`docs/03-firestore-schema.md`); this only
/// decides whether a row is well-formed enough to attempt at all.
///
/// Expected header row (case-insensitive, exact names):
/// `studentName, gender, dateOfBirth, grade, section, mediumOfInstruction,
/// language, electiveSubject, externalStudentCode`. `gender`, `dateOfBirth`,
/// `electiveSubject` and `externalStudentCode` are optional columns;
/// `dateOfBirth` is `YYYY-MM-DD`.
library;

import 'package:csv/csv.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_draft.dart';

const List<String> kRequiredCsvColumns = <String>[
  'studentName',
  'grade',
  'section',
  'mediumOfInstruction',
  'language',
];

const List<String> kOptionalCsvColumns = <String>[
  'gender',
  'dateOfBirth',
  'electiveSubject',
  'externalStudentCode',
];

/// A row that could not be turned into a [StudentImportRow] at all — a
/// missing required field or an unparseable date. Distinct from a
/// repository-level rejection (a duplicate or a business-rule failure),
/// which can only be known once the row is well-formed.
final class CsvRowError {
  const CsvRowError({required this.rowNumber, required this.reason});

  final int rowNumber;
  final String reason;
}

final class CsvParseOutcome {
  const CsvParseOutcome({required this.rows, required this.errors});

  final List<StudentImportRow> rows;
  final List<CsvRowError> errors;
}

final class CsvStudentParser {
  const CsvStudentParser();

  /// Returns `null` for [errors] at file level (missing a required column,
  /// the file has no data rows) rather than throwing — a parser is
  /// something a user's mistake reaches constantly, not an exceptional path.
  CsvParseOutcome parse(String content) {
    final List<List<dynamic>> rawRows = Csv().decode(content);
    if (rawRows.isEmpty) {
      return const CsvParseOutcome(
        rows: <StudentImportRow>[],
        errors: <CsvRowError>[
          CsvRowError(rowNumber: 0, reason: 'The file is empty.'),
        ],
      );
    }

    final List<String> header = rawRows.first
        .map((dynamic cell) => cell.toString().trim())
        .toList(growable: false);
    final Map<String, int> columnIndex = <String, int>{
      for (int i = 0; i < header.length; i++) header[i].toLowerCase(): i,
    };

    final List<String> missing = kRequiredCsvColumns
        .where((String c) => !columnIndex.containsKey(c.toLowerCase()))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      return CsvParseOutcome(
        rows: const <StudentImportRow>[],
        errors: <CsvRowError>[
          CsvRowError(
            rowNumber: 0,
            reason: 'Missing required column(s): ${missing.join(', ')}.',
          ),
        ],
      );
    }

    final List<StudentImportRow> rows = <StudentImportRow>[];
    final List<CsvRowError> errors = <CsvRowError>[];

    for (int i = 1; i < rawRows.length; i++) {
      final List<dynamic> raw = rawRows[i];
      if (raw.isEmpty ||
          (raw.length == 1 && raw.first.toString().trim().isEmpty)) {
        continue; // a trailing blank line is not a row
      }
      final int rowNumber = i; // header excluded, 1-based data row number
      String? cell(String column) {
        final int? index = columnIndex[column.toLowerCase()];
        if (index == null || index >= raw.length) {
          return null;
        }
        final String value = raw[index].toString().trim();
        return value.isEmpty ? null : value;
      }

      final String? studentName = cell('studentName');
      final String? grade = cell('grade');
      final String? section = cell('section');
      final String? medium = cell('mediumOfInstruction');
      final String? language = cell('language');
      if (studentName == null ||
          grade == null ||
          section == null ||
          medium == null ||
          language == null) {
        errors.add(
          CsvRowError(
            rowNumber: rowNumber,
            reason: 'Missing a required value (name, grade, section, '
                'medium or language).',
          ),
        );
        continue;
      }

      DateTime? dateOfBirth;
      final String? rawDob = cell('dateOfBirth');
      if (rawDob != null) {
        final DateTime? parsed = DateTime.tryParse(rawDob);
        // Normalised to midnight *UTC* on the same calendar date. A bare
        // `YYYY-MM-DD` parses as local time, and the dedupe key derives from
        // `dateOfBirth.toUtc()` — so east of Greenwich the same child would
        // hash to a different key than west of it, and a duplicate import
        // would be admitted as a new student (requirement §11).
        dateOfBirth = parsed == null
            ? null
            : DateTime.utc(parsed.year, parsed.month, parsed.day);
        if (dateOfBirth == null) {
          errors.add(
            CsvRowError(
              rowNumber: rowNumber,
              reason: "Date of birth '$rawDob' is not in YYYY-MM-DD format.",
            ),
          );
          continue;
        }
      }

      rows.add(
        StudentImportRow(
          rowNumber: rowNumber,
          draft: StudentDraft(
            studentName: studentName,
            gender: Gender.tryFromWireName(cell('gender')?.toUpperCase()),
            dateOfBirth: dateOfBirth,
            grade: grade,
            section: section,
            mediumOfInstruction: medium,
            language: language,
            electiveSubject: cell('electiveSubject'),
            externalStudentCode: cell('externalStudentCode'),
          ),
        ),
      );
    }

    return CsvParseOutcome(rows: rows, errors: errors);
  }
}
