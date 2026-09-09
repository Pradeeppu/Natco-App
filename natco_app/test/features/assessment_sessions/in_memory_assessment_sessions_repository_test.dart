/// Tests for [InMemoryAssessmentSessionsRepository]: the session lifecycle
/// state machine, scope isolation, and starting a session strictly from
/// already-downloaded [SessionPrerequisites].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/in_memory_assessment_sessions_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

void main() {
  const IdGenerator idGenerator = UuidIdGenerator();
  final Clock clock = FixedClock(DateTime.utc(2026, 9, 10));
  late InMemoryAssessmentSessionsRepository repo;

  SessionPrerequisites prerequisitesFor({
    required String schoolId,
    required String clusterId,
    required String districtId,
    required String stateId,
    Map<String, List<String>> roster = const <String, List<String>>{
      'A': <String>['s1', 's2'],
    },
  }) {
    final DateTime now = clock.nowUtc();
    final Assessment assessment = Assessment(
      assessmentId: idGenerator.newId(),
      assessmentName: 'Term 1 Math',
      assessmentCode: 'MATH-T1',
      academicYear: '2026-27',
      grade: '5',
      subject: 'Mathematics',
      questionCount: 3,
      questionType: QuestionType.mcqSingle,
      options: const <String>['A', 'B', 'C', 'D'],
      durationMinutes: 30,
      status: AssessmentStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    return SessionPrerequisites(
      assignmentId: idGenerator.newId(),
      assessment: assessment,
      questions: const <AssessmentQuestion>[],
      publishedAnswerKey: null,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      grade: '5',
      studentIdsBySection: roster,
      downloadedAt: now,
    );
  }

  setUp(() {
    repo = InMemoryAssessmentSessionsRepository(
      idGenerator: idGenerator,
      clock: clock,
    );
  });

  test('startSession creates a session at STARTED with the section roster', () async {
    final prerequisites = prerequisitesFor(
      schoolId: 'sch1',
      clusterId: 'cl1',
      districtId: 'di1',
      stateId: 'st1',
    );
    final result = await repo.startSession(
      prerequisites: prerequisites,
      section: 'A',
      expectedStudentCount: 2,
      teacherUserId: 'teacher1',
      deviceId: 'device1',
    );
    final AssessmentSession session = result.valueOrNull!;
    expect(session.status, SessionStatus.started);
    expect(session.studentIds, <String>['s1', 's2']);
    expect(session.startedAt, isNotNull);
    expect(session.schoolId, 'sch1');
  });

  test('startSession refuses a section not covered by the download', () async {
    final prerequisites = prerequisitesFor(
      schoolId: 'sch1',
      clusterId: 'cl1',
      districtId: 'di1',
      stateId: 'st1',
    );
    final result = await repo.startSession(
      prerequisites: prerequisites,
      section: 'Z',
      expectedStudentCount: 2,
      teacherUserId: 'teacher1',
      deviceId: 'device1',
    );
    expect(result.failureOrNull, isA<ValidationFailure>());
  });

  group('status transitions', () {
    late AssessmentSession session;

    setUp(() async {
      final prerequisites = prerequisitesFor(
        schoolId: 'sch1',
        clusterId: 'cl1',
        districtId: 'di1',
        stateId: 'st1',
      );
      final result = await repo.startSession(
        prerequisites: prerequisites,
        section: 'A',
        expectedStudentCount: 2,
        teacherUserId: 'teacher1',
        deviceId: 'device1',
      );
      session = result.valueOrNull!;
    });

    test('moves forward one legal step at a time', () async {
      final inProgress = await repo.setSessionStatus(
        session.sessionId,
        SessionStatus.inProgress,
      );
      expect(inProgress.valueOrNull?.status, SessionStatus.inProgress);

      final completed = await repo.setSessionStatus(
        session.sessionId,
        SessionStatus.completed,
      );
      expect(completed.valueOrNull?.status, SessionStatus.completed);
      expect(completed.valueOrNull?.endedAt, isNotNull);
    });

    test('rejects skipping a step', () async {
      final result = await repo.setSessionStatus(
        session.sessionId,
        SessionStatus.completed,
      );
      expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
    });

    test('rejects moving backward', () async {
      await repo.setSessionStatus(session.sessionId, SessionStatus.inProgress);
      await repo.setSessionStatus(session.sessionId, SessionStatus.completed);
      final result = await repo.setSessionStatus(
        session.sessionId,
        SessionStatus.inProgress,
      );
      expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
    });
  });

  test('a cluster-scoped caller only sees sessions at their schools', () async {
    final prerequisitesA = prerequisitesFor(
      schoolId: 'schA',
      clusterId: 'clA',
      districtId: 'diA',
      stateId: 'stA',
    );
    final prerequisitesB = prerequisitesFor(
      schoolId: 'schB',
      clusterId: 'clB',
      districtId: 'diA',
      stateId: 'stA',
    );
    await repo.startSession(
      prerequisites: prerequisitesA,
      section: 'A',
      expectedStudentCount: 2,
      teacherUserId: 'teacher1',
      deviceId: 'device1',
    );
    await repo.startSession(
      prerequisites: prerequisitesB,
      section: 'A',
      expectedStudentCount: 2,
      teacherUserId: 'teacher2',
      deviceId: 'device2',
    );

    final scopedToA = AccessScope.singleSchool('schA');
    final sessionsForA = await repo.listSessions(scope: scopedToA);
    expect(sessionsForA.valueOrNull, hasLength(1));
    expect(sessionsForA.valueOrNull!.single.schoolId, 'schA');

    final global = await repo.listSessions(scope: const AccessScope.global());
    expect(global.valueOrNull, hasLength(2));

    final onlyTeacher2 = await repo.listSessions(
      scope: const AccessScope.global(),
      teacherUserId: 'teacher2',
    );
    expect(onlyTeacher2.valueOrNull, hasLength(1));
    expect(onlyTeacher2.valueOrNull!.single.teacherUserId, 'teacher2');
  });

  test('getSession returns null for an unknown id, not a failure', () async {
    final result = await repo.getSession('missing');
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, isNull);
  });
}
