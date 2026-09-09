/// The single [StudentRepository] implementation.
///
/// Composes a swappable [StudentDataSource] with dedupe-key derivation,
/// ancestry resolution (via [SchoolHierarchyRepository]) and audit logging —
/// written once here rather than per backend, mirroring
/// `AuthRepositoryImpl`.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/students/data/service/student_data_source.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_draft.dart';
import 'package:natco_app/features/students/domain/entity/student_import_result.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';

final class StudentRepositoryImpl implements StudentRepository {
  StudentRepositoryImpl({
    required StudentDataSource dataSource,
    required SchoolHierarchyRepository schoolRepository,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _dataSource = dataSource,
       _schoolRepository = schoolRepository,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final StudentDataSource _dataSource;
  final SchoolHierarchyRepository _schoolRepository;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    String? schoolId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listStudents(
    scope: scope,
    schoolId: schoolId,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<Student>> getStudent(String studentId) =>
      _dataSource.getStudent(studentId);

  @override
  Future<Result<Set<String>>> existingDedupeKeys(Set<String> dedupeKeys) =>
      _dataSource.existingDedupeKeys(dedupeKeys);

  @override
  Future<Result<Student>> createStudent(
    StudentDraft draft, {
    required String schoolId,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<School> schoolResult = await _schoolRepository.getSchool(
      schoolId,
    );
    if (schoolResult.isFailure) {
      return err(schoolResult.failureOrNull!);
    }
    final Student student = _buildStudent(draft, schoolResult.valueOrNull!);
    final Result<Student> result = await _dataSource.createStudent(student);
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.studentCreated,
          entityId: student.studentId,
          actorUserId: actorUserId,
          actorRole: actorRole,
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<Student>> updateStudent(
    Student student, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<Student> result = await _dataSource.updateStudent(
      student.copyWith(updatedAt: _clock.nowUtc()),
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.studentUpdated,
          entityId: student.studentId,
          actorUserId: actorUserId,
          actorRole: actorRole,
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<StudentImportResult>> importStudents({
    required List<StudentImportRow> rows,
    required String schoolId,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<School> schoolResult = await _schoolRepository.getSchool(
      schoolId,
    );
    if (schoolResult.isFailure) {
      return err(schoolResult.failureOrNull!);
    }
    final School school = schoolResult.valueOrNull!;

    final List<Student> imported = <Student>[];
    final List<RejectedImportRow> rejected = <RejectedImportRow>[];

    // Every row is attempted independently: one rejected row must never
    // block the rest (requirement §11, §22).
    for (final StudentImportRow row in rows) {
      final Student student = _buildStudent(row.draft, school);
      final Result<Student> result = await _dataSource.createStudent(student);
      switch (result) {
        case Success<Student>(:final Student value):
          imported.add(value);
          await _auditSink.record(
            _event(
              AuditAction.studentCreated,
              entityId: value.studentId,
              actorUserId: actorUserId,
              actorRole: actorRole,
            ),
          );
        case FailureResult<Student>(:final Failure failure):
          rejected.add(RejectedImportRow(row: row, reason: failure));
      }
    }

    await _auditSink.record(
      _event(
        AuditAction.studentImportCompleted,
        entityId: schoolId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{
          'attempted': rows.length,
          'imported': imported.length,
          'rejected': rejected.length,
        },
      ),
    );

    return ok(StudentImportResult(imported: imported, rejected: rejected));
  }

  Student _buildStudent(StudentDraft draft, School school) {
    final DateTime now = _clock.nowUtc();
    final String dedupeKey = _idGenerator.dedupeKey(<String>[
      school.schoolId,
      draft.studentName,
      draft.grade,
      draft.section,
      draft.dateOfBirth?.toUtc().toIso8601String() ?? '',
    ]);
    return Student(
      studentId: _idGenerator.newId(),
      externalStudentCode: draft.externalStudentCode,
      studentName: draft.studentName,
      gender: draft.gender,
      dateOfBirth: draft.dateOfBirth,
      grade: draft.grade,
      section: draft.section,
      mediumOfInstruction: draft.mediumOfInstruction,
      language: draft.language,
      electiveSubject: draft.electiveSubject,
      schoolId: school.schoolId,
      clusterId: school.clusterId,
      districtId: school.districtId,
      stateId: school.stateId,
      activeStatus: true,
      dedupeKey: dedupeKey,
      createdAt: now,
      updatedAt: now,
    );
  }

  AuditEvent _event(
    AuditAction action, {
    required String entityId,
    required String actorUserId,
    required String actorRole,
    Map<String, Object?>? newValue,
  }) => AuditEvent(
    auditId: _idGenerator.newId(),
    userId: actorUserId,
    role: actorRole,
    action: action,
    entityType: 'student',
    entityId: entityId,
    timestamp: _clock.nowUtc(),
    deviceId: _deviceInfo.deviceId,
    appVersion: _deviceInfo.appVersion,
    newValue: newValue,
  );
}
