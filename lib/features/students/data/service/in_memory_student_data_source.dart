/// In-memory [StudentDataSource]. Backs demo mode and tests.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/data/service/student_data_source.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

final class InMemoryStudentDataSource implements StudentDataSource {
  InMemoryStudentDataSource({List<Student> students = const <Student>[]})
    : _students = <String, Student>{
        for (final Student s in students) s.studentId: s,
      },
      _dedupeKeys = <String>{for (final Student s in students) s.dedupeKey};

  final Map<String, Student> _students;
  final Set<String> _dedupeKeys;

  @override
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    String? schoolId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final String needle = query.trim().toLowerCase();
    final List<Student> matching =
        _students.values
            .where((Student s) => schoolId == null || s.schoolId == schoolId)
            .where(
              (Student s) => scope.covers(
                ScopeTarget(
                  stateId: s.stateId,
                  districtId: s.districtId,
                  clusterId: s.clusterId,
                  schoolId: s.schoolId,
                  grade: s.grade,
                  section: s.section,
                ),
              ),
            )
            .where(
              (Student s) =>
                  needle.isEmpty || s.studentName.toLowerCase().contains(needle),
            )
            .toList()
          ..sort((Student a, Student b) => a.studentName.compareTo(b.studentName));

    final int offset = cursor is int ? cursor : 0;
    final int end = (offset + pageSize).clamp(0, matching.length);
    final List<Student> items = offset >= matching.length
        ? const <Never>[]
        : matching.sublist(offset, end);
    final bool hasMore = end < matching.length;
    return ok((
      items: items,
      nextCursor: hasMore ? end : null,
      hasMore: hasMore,
    ));
  }

  @override
  Future<Result<Student>> getStudent(String studentId) async {
    final Student? student = _students[studentId];
    if (student == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That student could not be found.',
          entityType: 'student',
          entityId: studentId,
        ),
      );
    }
    return ok(student);
  }

  @override
  Future<Result<Student>> createStudent(Student student) async {
    if (_dedupeKeys.contains(student.dedupeKey)) {
      final Student existing = _students.values.firstWhere(
        (Student s) => s.dedupeKey == student.dedupeKey,
      );
      return err(
        DuplicateFailure(
          userMessage: 'This student has already been registered.',
          entityType: 'student',
          entityId: existing.studentId,
          details: <String, String>{
            'schoolId': existing.schoolId,
            'grade': existing.grade,
            'section': existing.section,
          },
        ),
      );
    }
    _students[student.studentId] = student;
    _dedupeKeys.add(student.dedupeKey);
    return ok(student);
  }

  @override
  Future<Result<Student>> updateStudent(Student student) async {
    final Student? existing = _students[student.studentId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That student could not be found.',
          entityType: 'student',
          entityId: student.studentId,
        ),
      );
    }
    if (existing.dedupeKey != student.dedupeKey) {
      return err(
        const ValidationFailure(
          userMessage: 'A student\'s identity cannot be changed this way.',
          diagnostic: 'attempted dedupeKey change on update',
        ),
      );
    }
    _students[student.studentId] = student;
    return ok(student);
  }

  @override
  Future<Result<Set<String>>> existingDedupeKeys(Set<String> dedupeKeys) async =>
      ok(dedupeKeys.where(_dedupeKeys.contains).toSet());
}
