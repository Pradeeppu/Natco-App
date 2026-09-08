/// In-memory [StudentsRepository].
///
/// Powers demo mode and the test suite. The behaviour under test most often
/// is duplicate rejection (requirement section 11): a second write for the
/// same school/name/grade/section/date-of-birth combination is refused, never
/// merged, with the existing record's identity attached to the failure so a
/// human can decide what to do.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_import_report.dart';
import 'package:natco_app/features/students/domain/repository/students_repository.dart';

final class InMemoryStudentsRepository implements StudentsRepository {
  InMemoryStudentsRepository({
    required IdGenerator idGenerator,
    required Clock clock,
    required InMemorySchoolsRepository schools,
  }) : _idGenerator = idGenerator,
       _clock = clock,
       _schools = schools;

  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Ancestry resolution only — see [InMemorySchoolsRepository.schoolByIdUnchecked].
  /// This is the in-memory equivalent of a Cloud Function reading a school
  /// with admin privileges to denormalise a new student's clusterId,
  /// districtId and stateId; it does not make student reads scope-free.
  final InMemorySchoolsRepository _schools;

  final Map<String, Student> _students = <String, Student>{};

  /// Dedupe key to the student already holding it, so a collision can report
  /// exactly which record it collided with (requirement section 22's spirit,
  /// applied to students rather than OMR sheets).
  final Map<String, String> _dedupeKeyToStudentId = <String, String>{};

  // ---------------------------------------------------------------- reads

  @override
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    required String schoolId,
    String? grade,
    String? section,
    String? query,
    PageRequest request = PageRequest.first,
  }) async {
    final String? needle = (query == null || query.trim().isEmpty)
        ? null
        : query.trim().toLowerCase();
    final List<Student> filtered = _students.values.where((Student s) {
      if (s.schoolId != schoolId) {
        return false;
      }
      if (!scope.covers(
        ScopeTarget(
          stateId: s.stateId,
          districtId: s.districtId,
          clusterId: s.clusterId,
          schoolId: s.schoolId,
          grade: s.grade,
          section: s.section,
        ),
      )) {
        return false;
      }
      if (grade != null && s.grade != grade) {
        return false;
      }
      if (section != null && s.section != section) {
        return false;
      }
      if (needle != null && !s.studentName.toLowerCase().contains(needle)) {
        return false;
      }
      return true;
    }).toList();

    // Sorted by name for a stable, human-sensible order; ties broken by id so
    // pagination cursors never land on an ambiguous boundary.
    filtered.sort((Student a, Student b) {
      final int byName = a.studentName.toLowerCase().compareTo(
        b.studentName.toLowerCase(),
      );
      return byName != 0 ? byName : a.studentId.compareTo(b.studentId);
    });

    int startIndex = 0;
    if (request.cursor != null) {
      final int cursorIndex = filtered.indexWhere(
        (Student s) => s.studentId == request.cursor,
      );
      startIndex = cursorIndex == -1 ? 0 : cursorIndex + 1;
    }
    final List<Student> pageItems = filtered
        .skip(startIndex)
        .take(request.limit)
        .toList(growable: false);
    final bool hasMore = startIndex + pageItems.length < filtered.length;
    return ok(
      Page<Student>(
        items: pageItems,
        nextCursor: hasMore ? pageItems.last.studentId : null,
      ),
    );
  }

  @override
  Future<Result<Student?>> getStudent(
    String studentId, {
    required AccessScope scope,
  }) async {
    final Student? student = _students[studentId];
    if (student == null) {
      return ok(null);
    }
    if (!scope.covers(
      ScopeTarget(
        stateId: student.stateId,
        districtId: student.districtId,
        clusterId: student.clusterId,
        schoolId: student.schoolId,
        grade: student.grade,
        section: student.section,
      ),
    )) {
      return err(PermissionFailure.outOfScope());
    }
    return ok(student);
  }

  // --------------------------------------------------------------- writes

  @override
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
  }) async {
    final school = _schools.schoolByIdUnchecked(schoolId);
    if (school == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: schoolId,
        ),
      );
    }

    final String dedupeKey = _idGenerator.dedupeKey(<String>[
      schoolId,
      studentName,
      grade,
      section,
      dateOfBirth?.toIso8601String() ?? '',
    ]);
    final String? collidingId = _dedupeKeyToStudentId[dedupeKey];
    if (collidingId != null) {
      final Student existing = _students[collidingId]!;
      return err(
        DuplicateFailure(
          userMessage:
              '"${existing.studentName}" is already enrolled in '
              '${existing.grade}-${existing.section} at this school.',
          entityType: 'student',
          entityId: existing.studentId,
          details: <String, String>{
            'Student': existing.studentName,
            'Grade': existing.grade,
            'Section': existing.section,
          },
        ),
      );
    }

    final DateTime now = _clock.nowUtc();
    final Student student = Student(
      studentId: _idGenerator.newId(),
      externalStudentCode: externalStudentCode,
      studentName: studentName,
      gender: gender,
      dateOfBirth: dateOfBirth,
      grade: grade,
      section: section,
      mediumOfInstruction: mediumOfInstruction,
      language: language,
      electiveSubject: electiveSubject,
      schoolId: schoolId,
      clusterId: school.clusterId,
      districtId: school.districtId,
      stateId: school.stateId,
      activeStatus: true,
      dedupeKey: dedupeKey,
      createdAt: now,
      updatedAt: now,
    );
    _students[student.studentId] = student;
    _dedupeKeyToStudentId[dedupeKey] = student.studentId;
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
    // A grade/section/name/dob edit changes the dedupe key. The old key is
    // released and the new one claimed, so the record still guards against a
    // fresh duplicate under its new identity — and an edit that would collide
    // with someone else is refused exactly like a create would be.
    final String newDedupeKey = _idGenerator.dedupeKey(<String>[
      existing.schoolId,
      student.studentName,
      student.grade,
      student.section,
      student.dateOfBirth?.toIso8601String() ?? '',
    ]);
    if (newDedupeKey != existing.dedupeKey) {
      final String? collidingId = _dedupeKeyToStudentId[newDedupeKey];
      if (collidingId != null && collidingId != existing.studentId) {
        final Student collision = _students[collidingId]!;
        return err(
          DuplicateFailure(
            userMessage:
                'This would match the existing record for '
                '"${collision.studentName}" in '
                '${collision.grade}-${collision.section}.',
            entityType: 'student',
            entityId: collision.studentId,
            details: <String, String>{
              'Student': collision.studentName,
              'Grade': collision.grade,
              'Section': collision.section,
            },
          ),
        );
      }
    }

    final Student updated = existing.copyWith(
      studentName: student.studentName,
      gender: student.gender,
      dateOfBirth: student.dateOfBirth,
      grade: student.grade,
      section: student.section,
      mediumOfInstruction: student.mediumOfInstruction,
      language: student.language,
      electiveSubject: student.electiveSubject,
      dedupeKey: newDedupeKey,
      updatedAt: _clock.nowUtc(),
    );
    _dedupeKeyToStudentId.remove(existing.dedupeKey);
    _dedupeKeyToStudentId[newDedupeKey] = updated.studentId;
    _students[updated.studentId] = updated;
    return ok(updated);
  }

  @override
  Future<Result<Student>> setStudentActive(
    String studentId,
    bool activeStatus,
  ) async {
    final Student? existing = _students[studentId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That student could not be found.',
          entityType: 'student',
          entityId: studentId,
        ),
      );
    }
    final Student updated = existing.copyWith(
      activeStatus: activeStatus,
      updatedAt: _clock.nowUtc(),
    );
    _students[studentId] = updated;
    return ok(updated);
  }

  // ------------------------------------------------------------- seeding

  /// Synchronous seeding path, mirroring
  /// `InMemorySchoolsRepository.seedSchool`.
  ///
  /// Deliberately not a thin wrapper around [createStudent]: that method is
  /// `async` for interface parity with the Firestore implementation, and
  /// calling it without awaiting relies on today's implementation happening
  /// to have no `await` in its body. That is exactly the kind of assumption
  /// that breaks silently the day someone adds simulated latency (as
  /// `InMemoryAuthService` already does) — the write would be lost with no
  /// error. This path is synchronous by its type, not by accident, so seed
  /// data can never be dropped that way.
  ///
  /// Still runs the dedupe check: a seed-data generator bug that produces a
  /// collision must fail loudly, not disappear.
  Student seedStudent({
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
  }) {
    final school = _schools.schoolByIdUnchecked(schoolId);
    if (school == null) {
      throw StateError('seedStudent: unknown schoolId "$schoolId"');
    }
    final String dedupeKey = _idGenerator.dedupeKey(<String>[
      schoolId,
      studentName,
      grade,
      section,
      dateOfBirth?.toIso8601String() ?? '',
    ]);
    if (_dedupeKeyToStudentId.containsKey(dedupeKey)) {
      throw StateError(
        'seedStudent: duplicate seed data for "$studentName" ($grade-$section)',
      );
    }
    final DateTime now = _clock.nowUtc();
    final Student student = Student(
      studentId: _idGenerator.newId(),
      externalStudentCode: externalStudentCode,
      studentName: studentName,
      gender: gender,
      dateOfBirth: dateOfBirth,
      grade: grade,
      section: section,
      mediumOfInstruction: mediumOfInstruction,
      language: language,
      electiveSubject: electiveSubject,
      schoolId: schoolId,
      clusterId: school.clusterId,
      districtId: school.districtId,
      stateId: school.stateId,
      activeStatus: true,
      dedupeKey: dedupeKey,
      createdAt: now,
      updatedAt: now,
    );
    _students[student.studentId] = student;
    _dedupeKeyToStudentId[dedupeKey] = student.studentId;
    return student;
  }

  @override
  Future<Result<StudentImportReport>> importStudents({
    required String schoolId,
    required List<StudentImportRow> rows,
  }) async {
    int createdCount = 0;
    final List<StudentImportRejection> rejections = <StudentImportRejection>[];

    for (final StudentImportRow row in rows) {
      final Result<Student> result = await createStudent(
        schoolId: schoolId,
        studentName: row.studentName,
        gender: Gender.fromWireName(row.gender?.toUpperCase()),
        grade: row.grade,
        section: row.section,
        mediumOfInstruction: row.mediumOfInstruction ?? '',
        language: row.language ?? '',
        dateOfBirth: row.dateOfBirth,
        electiveSubject: row.electiveSubject,
        externalStudentCode: row.externalStudentCode,
      );
      switch (result) {
        case Success<Student>():
          createdCount++;
        case FailureResult<Student>(:final Failure failure):
          rejections.add(
            StudentImportRejection(
              rowNumber: row.rowNumber,
              studentName: row.studentName,
              reason: failure is DuplicateFailure
                  ? ImportRejectionReason.duplicate
                  : ImportRejectionReason.other,
              detail: failure.userMessage,
            ),
          );
      }
    }

    return ok(
      StudentImportReport(
        totalRows: rows.length,
        createdCount: createdCount,
        parseErrors: const <StudentImportParseError>[],
        rejections: rejections,
      ),
    );
  }
}
