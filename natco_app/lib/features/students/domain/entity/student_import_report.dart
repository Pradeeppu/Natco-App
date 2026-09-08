/// The outcome of a CSV import (requirement section 11).
///
/// Rejected rows are reported, never silently merged into an existing
/// record — a duplicate found during import is exactly the case a human is
/// meant to look at (docs/02-data-model.md: "merging student identities
/// silently is a data-integrity failure").
library;

/// One parsed CSV row, before persistence.
final class StudentImportRow {
  const StudentImportRow({
    required this.rowNumber,
    required this.studentName,
    required this.grade,
    required this.section,
    this.gender,
    this.dateOfBirth,
    this.mediumOfInstruction,
    this.language,
    this.electiveSubject,
    this.externalStudentCode,
  });

  /// 1-based, counting the header row as row 1 — matches what a spreadsheet
  /// user sees, which is what the rejection report shows them.
  final int rowNumber;

  final String studentName;
  final String grade;
  final String section;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? mediumOfInstruction;
  final String? language;
  final String? electiveSubject;
  final String? externalStudentCode;
}

/// Why a row could not be parsed, before it ever reaches the repository.
final class StudentImportParseError {
  const StudentImportParseError({
    required this.rowNumber,
    required this.reason,
  });

  final int rowNumber;
  final String reason;
}

/// Why a parsed row was rejected at the point of persistence.
enum ImportRejectionReason {
  /// A student with the same school, name, grade, section and date of birth
  /// already exists.
  duplicate,

  /// The repository refused for some other reason (out of scope, storage
  /// failure).
  other,
}

final class StudentImportRejection {
  const StudentImportRejection({
    required this.rowNumber,
    required this.studentName,
    required this.reason,
    required this.detail,
  });

  final int rowNumber;
  final String studentName;
  final ImportRejectionReason reason;

  /// Plain-language explanation shown next to the row.
  final String detail;
}

/// The full report shown to the person who ran the import.
final class StudentImportReport {
  const StudentImportReport({
    required this.totalRows,
    required this.createdCount,
    required this.parseErrors,
    required this.rejections,
  });

  final int totalRows;
  final int createdCount;
  final List<StudentImportParseError> parseErrors;
  final List<StudentImportRejection> rejections;

  int get failedCount => parseErrors.length + rejections.length;

  bool get hasFailures => failedCount > 0;

  bool get isFullSuccess => createdCount == totalRows && !hasFailures;
}
