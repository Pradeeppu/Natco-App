/// A student's identity and enrolment fields, before it has a
/// `studentId`/`dedupeKey`/school assignment of its own.
///
/// Used both by the manual "add student" form and by a parsed CSV row — the
/// two ways a new student enters the system ask for exactly the same fields
/// (docs/02-data-model.md §3).
library;

import 'package:natco_app/features/students/domain/entity/student.dart';

final class StudentDraft {
  const StudentDraft({
    required this.studentName,
    required this.grade,
    required this.section,
    required this.mediumOfInstruction,
    required this.language,
    this.gender = Gender.notSpecified,
    this.dateOfBirth,
    this.electiveSubject,
    this.externalStudentCode,
  });

  final String studentName;
  final Gender gender;
  final DateTime? dateOfBirth;
  final String grade;
  final String section;
  final String mediumOfInstruction;
  final String language;
  final String? electiveSubject;
  final String? externalStudentCode;
}

/// One row of a CSV import, carrying its 1-based source line number so a
/// rejection can be reported as "row 14: ..." rather than losing its place
/// in the file.
final class StudentImportRow {
  const StudentImportRow({required this.rowNumber, required this.draft});

  final int rowNumber;
  final StudentDraft draft;
}
