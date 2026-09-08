/// Student master data, as seen by the presentation layer.
library;

import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_import_report.dart';

abstract interface class StudentsRepository {
  /// Lists students in [schoolId], optionally narrowed by grade/section and a
  /// name search. Always paginated (requirement section 42): a 2,000-student
  /// school is scrolled, never loaded whole.
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    required String schoolId,
    String? grade,
    String? section,
    String? query,
    PageRequest request = PageRequest.first,
  });

  Future<Result<Student?>> getStudent(String studentId, {required AccessScope scope});

  /// Creates one student. Fails with a [DuplicateFailure] carrying the
  /// existing record's identity when the school/name/grade/section/dob
  /// combination already exists (requirement section 11) — the caller never
  /// silently merges.
  Future<Result<Student>> createStudent({
    required String schoolId,
    required String studentName,
    required Gender gender,
    required String grade,
    required String section,
    required String mediumOfInstruction,
    required String language,
    DateTime? dateOfBirth,
    String? electiveSubject,
    String? externalStudentCode,
  });

  Future<Result<Student>> updateStudent(Student student);

  Future<Result<Student>> setStudentActive(String studentId, bool activeStatus);

  /// Imports every row in [rows] against [schoolId], skipping duplicates
  /// rather than merging them. Never partially applies a row — each row
  /// either becomes a new student or appears in the report's rejections.
  Future<Result<StudentImportReport>> importStudents({
    required String schoolId,
    required List<StudentImportRow> rows,
  });
}
