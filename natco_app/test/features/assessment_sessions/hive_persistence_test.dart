/// The real "survives force-stop" proof.
///
/// A widget test can only simulate a killed app by rebuilding a
/// `ProviderContainer`, which never actually leaves memory — it proves
/// nothing about disk durability. This test instead opens a genuine Hive
/// box on a temp directory, writes through the real repositories, fully
/// closes Hive (the same call a killed process leaves undone, and the
/// closest a plain `flutter test` can get to "the app was killed and
/// relaunched"), reopens against the same directory, and asserts the data
/// is still there, unchanged.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/hive_assessment_sessions_repository.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/hive_session_prerequisites_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

void main() {
  late Directory tempDir;
  const IdGenerator idGenerator = UuidIdGenerator();
  final Clock clock = FixedClock(DateTime.utc(2026, 9, 10, 9));
  final AppLogger logger = AppLogger(minimumLevel: LogLevel.error, sinks: const []);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('natco_hive_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  SessionPrerequisites buildPrerequisites() {
    final DateTime now = clock.nowUtc();
    return SessionPrerequisites(
      assignmentId: 'assignment-1',
      assessment: Assessment(
        assessmentId: 'assessment-1',
        assessmentName: 'Term 1 Math',
        assessmentCode: 'MATH-T1',
        academicYear: '2026-27',
        grade: '5',
        subject: 'Mathematics',
        questionCount: 2,
        questionType: QuestionType.mcqSingle,
        options: const <String>['A', 'B', 'C', 'D'],
        durationMinutes: 30,
        status: AssessmentStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
      questions: const <AssessmentQuestion>[],
      publishedAnswerKey: null,
      schoolId: 'school-1',
      clusterId: 'cluster-1',
      districtId: 'district-1',
      stateId: 'state-1',
      grade: '5',
      studentIdsBySection: const <String, List<String>>{
        'A': <String>['student-1', 'student-2'],
      },
      downloadedAt: now,
    );
  }

  test('a started session survives closing and reopening the Hive box', () async {
    final HiveAssessmentSessionsRepository beforeRestart =
        HiveAssessmentSessionsRepository(
          hive: Hive,
          idGenerator: idGenerator,
          clock: clock,
          logger: logger,
        );

    final started = await beforeRestart.startSession(
      prerequisites: buildPrerequisites(),
      section: 'A',
      expectedStudentCount: 2,
      teacherUserId: 'teacher-1',
      deviceId: 'device-1',
    );
    final String sessionId = started.valueOrNull!.sessionId;
    final inProgress = await beforeRestart.setSessionStatus(
      sessionId,
      SessionStatus.inProgress,
    );
    expect(inProgress.valueOrNull?.status, SessionStatus.inProgress);

    // The moment a real force-stop happens: every open box is gone from
    // memory, but the directory on disk is untouched.
    await Hive.close();

    final HiveAssessmentSessionsRepository afterRestart =
        HiveAssessmentSessionsRepository(
          hive: Hive,
          idGenerator: idGenerator,
          clock: clock,
          logger: logger,
        );
    final recovered = await afterRestart.getSession(sessionId);
    final AssessmentSession? session = recovered.valueOrNull;

    expect(session, isNotNull);
    expect(session!.status, SessionStatus.inProgress);
    expect(session.studentIds, <String>['student-1', 'student-2']);
    expect(session.schoolId, 'school-1');
    expect(session.teacherUserId, 'teacher-1');

    // The recovered repository is fully functional too, not read-only.
    final completed = await afterRestart.setSessionStatus(
      sessionId,
      SessionStatus.completed,
    );
    expect(completed.valueOrNull?.status, SessionStatus.completed);
    expect(completed.valueOrNull?.endedAt, isNotNull);
  });

  test('listSessions after reopening still applies scope correctly', () async {
    final HiveAssessmentSessionsRepository beforeRestart =
        HiveAssessmentSessionsRepository(
          hive: Hive,
          idGenerator: idGenerator,
          clock: clock,
          logger: logger,
        );
    await beforeRestart.startSession(
      prerequisites: buildPrerequisites(),
      section: 'A',
      expectedStudentCount: 2,
      teacherUserId: 'teacher-1',
      deviceId: 'device-1',
    );
    await Hive.close();

    final HiveAssessmentSessionsRepository afterRestart =
        HiveAssessmentSessionsRepository(
          hive: Hive,
          idGenerator: idGenerator,
          clock: clock,
          logger: logger,
        );
    final inScope = await afterRestart.listSessions(
      scope: AccessScope.singleSchool('school-1'),
    );
    expect(inScope.valueOrNull, hasLength(1));

    final outOfScope = await afterRestart.listSessions(
      scope: AccessScope.singleSchool('a-different-school'),
    );
    expect(outOfScope.valueOrNull, isEmpty);
  });

  test('downloaded session prerequisites survive closing and reopening the Hive box', () async {
    final HiveSessionPrerequisitesRepository beforeRestart =
        HiveSessionPrerequisitesRepository(hive: Hive, logger: logger);
    final SessionPrerequisites prerequisites = buildPrerequisites();
    await beforeRestart.save(prerequisites);

    await Hive.close();

    final HiveSessionPrerequisitesRepository afterRestart =
        HiveSessionPrerequisitesRepository(hive: Hive, logger: logger);
    final recovered = await afterRestart.get(prerequisites.assignmentId);
    final SessionPrerequisites? result = recovered.valueOrNull;

    expect(result, isNotNull);
    expect(result!.assessment.assessmentId, prerequisites.assessment.assessmentId);
    expect(result.studentIdsBySection, prerequisites.studentIdsBySection);
    expect(result.schoolId, prerequisites.schoolId);

    final all = await afterRestart.listDownloaded();
    expect(all.valueOrNull, hasLength(1));
  });
}
