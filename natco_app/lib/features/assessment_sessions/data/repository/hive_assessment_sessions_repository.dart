/// Hive-backed [AssessmentSessionsRepository].
///
/// Every write is a single `Box.put` of the whole session, so a session is
/// always either fully the old state or fully the new one on disk — there is
/// no multi-step commit for a crash to land in between (docs/06-offline-sync-
/// strategy.md §1). This is what "a session survives the app being killed"
/// means concretely: the next launch reopens the same box and reads back
/// exactly what was last written, with no separate recovery step needed for
/// the entity itself.
library;

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/assessment_sessions_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class HiveAssessmentSessionsRepository
    implements AssessmentSessionsRepository {
  HiveAssessmentSessionsRepository({
    required HiveInterface hive,
    required IdGenerator idGenerator,
    required Clock clock,
    required AppLogger logger,
  }) : _hive = hive,
       _idGenerator = idGenerator,
       _clock = clock,
       _logger = logger;

  final HiveInterface _hive;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final AppLogger _logger;

  @override
  Future<Result<List<AssessmentSession>>> listSessions({
    required AccessScope scope,
    String? teacherUserId,
  }) => guardAsync(() async {
    final Box<String> box = await _openBox();
    final List<AssessmentSession> sessions = <AssessmentSession>[
      for (final String raw in box.values)
        if (_decode(box, raw) case final AssessmentSession s) s,
    ];
    final List<AssessmentSession> filtered = sessions.where((
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
    return filtered;
  }, onError: _mapError);

  @override
  Future<Result<AssessmentSession?>> getSession(String sessionId) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        final String? raw = box.get(sessionId);
        return raw == null ? null : _decode(box, raw, key: sessionId);
      }, onError: _mapError);

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
    return _write(session);
  }

  @override
  Future<Result<AssessmentSession>> setSessionStatus(
    String sessionId,
    SessionStatus next,
  ) async {
    final Result<AssessmentSession?> current = await getSession(sessionId);
    if (current.isFailure) {
      return err(current.failureOrNull!);
    }
    final AssessmentSession? existing = current.valueOrNull;
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
    return _write(updated);
  }

  Future<Result<AssessmentSession>> _write(AssessmentSession session) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        await box.put(session.sessionId, jsonEncode(session.toJson()));
        return session;
      }, onError: _mapError);

  AssessmentSession? _decode(Box<String> box, String raw, {String? key}) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      _logger.warning('assessment_session_malformed');
      if (key != null) {
        box.delete(key);
      }
      return null;
    }
    final AssessmentSession? session = AssessmentSession.tryFromJson(decoded);
    if (session == null) {
      _logger.warning('assessment_session_unreadable');
      if (key != null) {
        box.delete(key);
      }
    }
    return session;
  }

  Future<Box<String>> _openBox() async => _hive.isBoxOpen(LocalBoxes.sessions)
      ? _hive.box<String>(LocalBoxes.sessions)
      : _hive.openBox<String>(LocalBoxes.sessions);

  Failure _mapError(Object error, StackTrace stackTrace) =>
      StorageFailure.localWrite(
        diagnostic: 'assessment sessions: $error',
        cause: error,
      );
}
