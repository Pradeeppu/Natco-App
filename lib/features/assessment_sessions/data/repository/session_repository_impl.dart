/// The single [SessionRepository] implementation.
///
/// Every write goes to [SessionStore] — Hive on a device, in-memory in tests
/// and demo mode — before this method returns. Nothing here waits on a
/// network; the sync engine (phase 9) reads from the same store afterwards
/// and uploads independently. This is what Critical Rule 12 means in code: a
/// session is durable the instant this repository says it is.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/data/service/session_store.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/repository/assessment_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';

final class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl({
    required AssessmentSessionStore store,
    required AssessmentRepository assessmentRepository,
    required SchoolHierarchyRepository schoolRepository,
    required StudentRepository studentRepository,
    required SyncQueueRepository syncQueue,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _store = store,
       _assessmentRepository = assessmentRepository,
       _schoolRepository = schoolRepository,
       _studentRepository = studentRepository,
       _syncQueue = syncQueue,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final AssessmentSessionStore _store;
  final AssessmentRepository _assessmentRepository;
  final SchoolHierarchyRepository _schoolRepository;
  final StudentRepository _studentRepository;
  final SyncQueueRepository _syncQueue;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<List<AssessmentSession>>> listSessions({
    required AccessScope scope,
    String? assessmentId,
    bool openOnly = false,
  }) async {
    final Result<List<AssessmentSession>> all = await _store.all();
    return all.map(
      (List<AssessmentSession> sessions) => sessions
          .where(
            (AssessmentSession s) =>
                assessmentId == null || s.assessmentId == assessmentId,
          )
          .where((AssessmentSession s) => !openOnly || s.status.isOpen)
          .where(
            (AssessmentSession s) => scope.covers(
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
          .toList(growable: false),
    );
  }

  @override
  Future<Result<AssessmentSession>> getSession(String sessionId) async {
    final Result<AssessmentSession?> result = await _store.read(sessionId);
    return switch (result) {
      FailureResult<AssessmentSession?>(:final Failure failure) => err(failure),
      Success<AssessmentSession?>(value: null) => err(
        NotFoundFailure(
          userMessage: 'That session could not be found.',
          entityType: 'assessment_session',
          entityId: sessionId,
        ),
      ),
      Success<AssessmentSession?>(:final AssessmentSession? value) =>
        ok(value!),
    };
  }

  @override
  Future<Result<AssessmentSession>> createSession({
    required String assessmentId,
    required String schoolId,
    required String grade,
    required String section,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<Assessment> assessmentResult = await _assessmentRepository
        .getAssessment(assessmentId);
    if (assessmentResult.isFailure) {
      return err(assessmentResult.failureOrNull!);
    }
    final Assessment assessment = assessmentResult.valueOrNull!;
    if (!assessment.isReadyForSessions) {
      return err(
        ValidationFailure(
          userMessage: assessment.hasPublishedKey
              ? 'This assessment is ${assessment.status.displayName.toLowerCase()} '
                    'and cannot be sat right now.'
              : 'This assessment has no published answer key yet. A session '
                    'cannot be scored without one.',
          diagnostic: 'session start refused: ${assessment.status.wireName}',
        ),
      );
    }

    final Result<School> schoolResult = await _schoolRepository.getSchool(
      schoolId,
    );
    if (schoolResult.isFailure) {
      return err(schoolResult.failureOrNull!);
    }
    final School school = schoolResult.valueOrNull!;

    // The roster is copied onto the session at creation, not referenced live:
    // it must render with no network, and a child who transfers out next
    // week must not disappear from a sitting they actually sat.
    final Result<List<Student>> rosterSource = await _classRoster(
      schoolId: schoolId,
      grade: grade,
      section: section,
    );
    if (rosterSource.isFailure) {
      return err(rosterSource.failureOrNull!);
    }
    final List<Student> students = rosterSource.valueOrNull!;
    if (students.isEmpty) {
      return err(
        const ValidationFailure(
          userMessage:
              'No students are registered in this class yet. Add students '
              'before starting a session.',
          diagnostic: 'session start with empty roster',
        ),
      );
    }

    final DateTime now = _clock.nowUtc();
    final AssessmentSession session = AssessmentSession(
      sessionId: _idGenerator.newId(),
      assessmentId: assessmentId,
      answerKeyVersion: assessment.publishedAnswerKeyVersion!,
      schoolId: school.schoolId,
      clusterId: school.clusterId,
      districtId: school.districtId,
      stateId: school.stateId,
      grade: grade,
      section: section,
      roster: students
          .map(
            (Student s) => SessionRosterEntry(
              studentId: s.studentId,
              studentName: s.studentName,
              grade: s.grade,
              section: s.section,
            ),
          )
          .toList(growable: false),
      status: SessionStatus.ready,
      conductedBy: actorUserId,
      deviceId: _deviceInfo.deviceId,
      createdAt: now,
      updatedAt: now,
    );

    final Result<AssessmentSession> written = await _store.write(session);
    if (written.isSuccess) {
      await _syncQueue.enqueue(
        SyncQueueEntry(
          syncId: _idGenerator.newId(),
          entityType: SyncEntityType.assessmentSession,
          entityId: session.sessionId,
          operation: SyncOperation.create,
          payloadRef: 'local/sessions/${session.sessionId}',
          idempotencyKey: 'create_session_${session.sessionId}',
          createdAt: now,
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );
      await _record(
        AuditAction.sessionCreated,
        session.sessionId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{
          'assessmentId': assessmentId,
          'rosterSize': students.length,
        },
      );
    }
    return written;
  }

  Future<Result<List<Student>>> _classRoster({
    required String schoolId,
    required String grade,
    required String section,
  }) async {
    // A session is created from within the caller's own school, so a global
    // scope is safe here: the school itself was already resolved through a
    // repository the caller's permission and scope were checked against, and
    // `schoolId` below narrows the query to exactly that school regardless.
    final Result<Page<Student>> page = await _studentRepository.listStudents(
      scope: const AccessScope.global(),
      schoolId: schoolId,
      pageSize: 500,
    );
    return page.map(
      (Page<Student> p) => p.items
          .where((Student s) => s.grade == grade && s.section == section)
          .toList(growable: false),
    );
  }

  @override
  Future<Result<AssessmentSession>> changeStatus(
    String sessionId, {
    required SessionStatus next,
    String? reason,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<AssessmentSession> currentResult = await getSession(
      sessionId,
    );
    if (currentResult.isFailure) {
      return err(currentResult.failureOrNull!);
    }
    final AssessmentSession current = currentResult.valueOrNull!;

    if (!current.status.canTransitionTo(next)) {
      return err(
        IllegalStateTransitionFailure(
          entityType: 'assessment_session',
          from: current.status.wireName,
          to: next.wireName,
          diagnostic:
              '${current.status.wireName} cannot become ${next.wireName}',
        ),
      );
    }
    if (next == SessionStatus.completed && !current.isFullyAccountedFor) {
      return err(
        ValidationFailure(
          userMessage:
              '${current.pendingCount} student(s) have not been captured or '
              'marked absent yet. Every student needs one or the other before '
              'this session can be completed.',
          diagnostic: 'completion attempted with ${current.pendingCount} pending',
        ),
      );
    }
    if (next == SessionStatus.abandoned &&
        (reason == null || reason.trim().isEmpty)) {
      return err(
        const ValidationFailure(
          userMessage:
              'Say why this session is being abandoned. Sheets already '
              'captured are kept either way.',
          fieldErrors: <String, String>{
            'reason': 'Enter a reason.',
          },
          diagnostic: 'abandon with no reason',
        ),
      );
    }

    final DateTime now = _clock.nowUtc();
    final AssessmentSession updated = current.copyWith(
      status: next,
      startedAt: next == SessionStatus.inProgress ? now : current.startedAt,
      endedAt:
          (next == SessionStatus.completed || next == SessionStatus.abandoned)
          ? now
          : current.endedAt,
      abandonReason: next == SessionStatus.abandoned ? reason : null,
      updatedAt: now,
    );

    final Result<AssessmentSession> written = await _store.write(updated);
    if (written.isSuccess) {
      await _syncQueue.enqueue(
        SyncQueueEntry(
          syncId: _idGenerator.newId(),
          entityType: SyncEntityType.assessmentSession,
          entityId: sessionId,
          operation: SyncOperation.update,
          payloadRef: 'local/sessions/$sessionId',
          idempotencyKey: 'update_session_${sessionId}_status_${next.wireName}',
          createdAt: now,
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );
      await _record(
        next == SessionStatus.abandoned
            ? AuditAction.sessionAbandoned
            : AuditAction.sessionStatusChanged,
        sessionId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        oldValue: <String, Object?>{'status': current.status.wireName},
        newValue: <String, Object?>{
          'status': next.wireName,
          'reason': ?reason,
        },
      );
    }
    return written;
  }

  @override
  Future<Result<AssessmentSession>> setAttendance(
    String sessionId, {
    required String studentId,
    required AttendanceState attendance,
    String? note,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<AssessmentSession> currentResult = await getSession(
      sessionId,
    );
    if (currentResult.isFailure) {
      return err(currentResult.failureOrNull!);
    }
    final AssessmentSession current = currentResult.valueOrNull!;
    if (!current.status.acceptsCapture && current.status != SessionStatus.ready) {
      return err(
        ValidationFailure(
          userMessage:
              'This session is ${current.status.displayName.toLowerCase()} and '
              'attendance can no longer be changed.',
          diagnostic: 'attendance change on ${current.status.wireName}',
        ),
      );
    }
    final SessionRosterEntry? entry = current.entryFor(studentId);
    if (entry == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That student is not on this session\'s roster.',
          entityType: 'session_roster_entry',
          entityId: studentId,
        ),
      );
    }
    if (entry.omrId != null && attendance != AttendanceState.captured) {
      // The sheet is evidence they were there. A record that says both
      // "absent" and "has a captured sheet" is a record nobody can act on.
      return err(
        ValidationFailure(
          userMessage:
              'A sheet has already been captured for this student, so they '
              'cannot be marked absent.',
          diagnostic: 'absent-with-omr attempted for $studentId',
        ),
      );
    }

    final List<SessionRosterEntry> roster = current.roster
        .map(
          (SessionRosterEntry e) => e.studentId == studentId
              ? e.copyWith(attendance: attendance, absenceNote: note)
              : e,
        )
        .toList(growable: false);
    final Result<AssessmentSession> written = await _store.write(
      current.copyWith(roster: roster, updatedAt: _clock.nowUtc()),
    );
    if (written.isSuccess) {
      await _syncQueue.enqueue(
        SyncQueueEntry(
          syncId: _idGenerator.newId(),
          entityType: SyncEntityType.assessmentSession,
          entityId: sessionId,
          operation: SyncOperation.update,
          payloadRef: 'local/sessions/$sessionId',
          idempotencyKey: 'update_session_${sessionId}_attendance_$studentId',
          createdAt: _clock.nowUtc(),
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );
      await _record(
        AuditAction.sessionAttendanceMarked,
        sessionId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{
          'studentId': studentId,
          'attendance': attendance.wireName,
        },
      );
    }
    return written;
  }

  @override
  Future<Result<AssessmentSession>> attachOmr(
    String sessionId, {
    required String studentId,
    required String omrId,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<AssessmentSession> currentResult = await getSession(
      sessionId,
    );
    if (currentResult.isFailure) {
      return err(currentResult.failureOrNull!);
    }
    final AssessmentSession current = currentResult.valueOrNull!;
    if (!current.status.acceptsCapture) {
      return err(
        ValidationFailure(
          userMessage:
              'This session is ${current.status.displayName.toLowerCase()} and '
              'cannot accept a new sheet.',
          diagnostic: 'capture attempted on ${current.status.wireName}',
        ),
      );
    }
    if (current.entryFor(studentId) == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That student is not on this session\'s roster.',
          entityType: 'session_roster_entry',
          entityId: studentId,
        ),
      );
    }

    final List<SessionRosterEntry> roster = current.roster
        .map(
          (SessionRosterEntry e) => e.studentId == studentId
              ? e.copyWith(attendance: AttendanceState.captured, omrId: omrId)
              : e,
        )
        .toList(growable: false);
    final Result<AssessmentSession> written = await _store.write(
      current.copyWith(roster: roster, updatedAt: _clock.nowUtc()),
    );
    if (written.isSuccess) {
      await _syncQueue.enqueue(
        SyncQueueEntry(
          syncId: _idGenerator.newId(),
          entityType: SyncEntityType.assessmentSession,
          entityId: sessionId,
          operation: SyncOperation.update,
          payloadRef: 'local/sessions/$sessionId',
          idempotencyKey: 'update_session_${sessionId}_omr_$studentId',
          createdAt: _clock.nowUtc(),
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );
    }
    return written;
  }

  Future<void> _record(
    AuditAction action,
    String sessionId, {
    required String actorUserId,
    required String actorRole,
    Map<String, Object?>? oldValue,
    Map<String, Object?>? newValue,
  }) => _auditSink.record(
    AuditEvent(
      auditId: _idGenerator.newId(),
      userId: actorUserId,
      role: actorRole,
      action: action,
      entityType: 'assessment_session',
      entityId: sessionId,
      timestamp: _clock.nowUtc(),
      deviceId: _deviceInfo.deviceId,
      appVersion: _deviceInfo.appVersion,
      oldValue: oldValue,
      newValue: newValue,
    ),
  );
}
