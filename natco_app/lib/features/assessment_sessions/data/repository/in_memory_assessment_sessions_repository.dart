/// In-memory [AssessmentSessionsRepository]. Used by demo mode and the test
/// suite — sessions do not survive a real process restart here, which is
/// exactly right for demo/tests (docs/08-mvp-implementation-plan.md: Phase 1
/// established that demo runs the whole app on in-memory services). The
/// "survives force-stop" exit criterion is proven against
/// `HiveAssessmentSessionsRepository`, the implementation real builds use.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/assessment_sessions_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class InMemoryAssessmentSessionsRepository
    implements AssessmentSessionsRepository {
  InMemoryAssessmentSessionsRepository({
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _idGenerator = idGenerator,
       _clock = clock;

  final IdGenerator _idGenerator;
  final Clock _clock;

  final Map<String, AssessmentSession> _sessions = <String, AssessmentSession>{};

  @override
  Future<Result<List<AssessmentSession>>> listSessions({
    required AccessScope scope,
    String? teacherUserId,
  }) async {
    final List<AssessmentSession> filtered = _sessions.values.where((
      AssessmentSession s,
    ) {
      if (teacherUserId != null && s.teacherUserId != teacherUserId) {
        return false;
      }
      return scope.covers(
        ScopeTarget(
          stateId: s.stateId,
          districtId: s.districtId,
          clusterId: s.clusterId,
          schoolId: s.schoolId,
          grade: s.grade,
          section: s.section,
        ),
      );
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ok(filtered);
  }

  @override
  Future<Result<AssessmentSession?>> getSession(String sessionId) async =>
      ok(_sessions[sessionId]);

  @override
  Future<Result<AssessmentSession>> startSession({
    required SessionPrerequisites prerequisites,
    required String section,
    required int expectedStudentCount,
    required String teacherUserId,
    required String deviceId,
  }) async {
    final List<String>? studentIds = prerequisites.studentIdsBySection[section];
    if (studentIds == null) {
      return err(
        ValidationFailure(
          userMessage: 'Section "$section" was not part of the download.',
        ),
      );
    }
    final DateTime now = _clock.nowUtc();
    final AssessmentSession session = AssessmentSession(
      sessionId: _idGenerator.newId(),
      assessmentId: prerequisites.assessment.assessmentId,
      schoolId: prerequisites.schoolId,
      clusterId: prerequisites.clusterId,
      districtId: prerequisites.districtId,
      stateId: prerequisites.stateId,
      grade: prerequisites.grade,
      section: section,
      subject: prerequisites.assessment.subject,
      academicYear: prerequisites.assessment.academicYear,
      assessmentDate: now,
      teacherUserId: teacherUserId,
      studentIds: studentIds,
      expectedStudentCount: expectedStudentCount,
      startedAt: now,
      status: SessionStatus.started,
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    _sessions[session.sessionId] = session;
    return ok(session);
  }

  @override
  Future<Result<AssessmentSession>> setSessionStatus(
    String sessionId,
    SessionStatus next,
  ) async {
    final AssessmentSession? existing = _sessions[sessionId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That session could not be found.',
          entityType: 'session',
          entityId: sessionId,
        ),
      );
    }
    if (!existing.status.canTransitionTo(next)) {
      return err(
        IllegalStateTransitionFailure(
          entityType: 'session',
          from: existing.status.wireName,
          to: next.wireName,
        ),
      );
    }
    final DateTime now = _clock.nowUtc();
    final AssessmentSession updated = existing.copyWith(
      status: next,
      updatedAt: now,
      endedAt: next == SessionStatus.completed ? now : null,
    );
    _sessions[sessionId] = updated;
    return ok(updated);
  }
}
