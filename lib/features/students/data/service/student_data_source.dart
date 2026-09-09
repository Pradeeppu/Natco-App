/// Raw student CRUD and paged queries, with no audit logging or ancestry
/// resolution — the swappable half of student data access.
/// `StudentRepositoryImpl` composes this with a `SchoolHierarchyRepository`
/// (to resolve a school's ancestry) and an `AuditSink`, mirroring the
/// `AuthService`/`AuthRepositoryImpl` split.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

abstract interface class StudentDataSource {
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    String? schoolId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<Student>> getStudent(String studentId);

  /// Creates [student], guarding `dedupeKey` uniqueness in the same
  /// transaction as the write (docs/03-firestore-schema.md). Returns
  /// [DuplicateFailure] — never overwrites — when the key already exists.
  Future<Result<Student>> createStudent(Student student);

  /// Updates an existing student. Implementations must refuse a change to
  /// `dedupeKey` (docs/04-security-model.md), matching what
  /// `firebase/firestore.rules` already enforces server-side.
  Future<Result<Student>> updateStudent(Student student);

  Future<Result<Set<String>>> existingDedupeKeys(Set<String> dedupeKeys);
}
