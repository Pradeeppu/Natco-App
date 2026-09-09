/// Student master data (docs/02-data-model.md §3, requirement §11).
///
/// See `SchoolHierarchyRepository` for why `list*` takes the caller's own
/// [AccessScope] rather than discovering it, and why mutations take
/// `actorUserId`/`actorRole`.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_draft.dart';
import 'package:natco_app/features/students/domain/entity/student_import_result.dart';

abstract interface class StudentRepository {
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    String? schoolId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<Student>> getStudent(String studentId);

  /// Creates one student under [schoolId]. The repository derives the
  /// cluster/district/state ancestry from the school and computes
  /// `dedupeKey` itself — a second write for the same child collides on the
  /// `student_dedupe` guard document rather than creating a twin
  /// (docs/03-firestore-schema.md).
  Future<Result<Student>> createStudent(
    StudentDraft draft, {
    required String schoolId,
    required String actorUserId,
    required String actorRole,
  });

  /// Updates an existing student. `dedupeKey` never changes on update — the
  /// Firestore rule refuses it and this method must not attempt to
  /// (docs/04-security-model.md).
  Future<Result<Student>> updateStudent(
    Student student, {
    required String actorUserId,
    required String actorRole,
  });

  /// The subset of [dedupeKeys] that already exist, so a CSV preview can
  /// flag duplicates before anything is committed.
  Future<Result<Set<String>>> existingDedupeKeys(Set<String> dedupeKeys);

  /// Imports [rows] under [schoolId]. Every row is attempted independently.
  Future<Result<StudentImportResult>> importStudents({
    required List<StudentImportRow> rows,
    required String schoolId,
    required String actorUserId,
    required String actorRole,
  });
}
