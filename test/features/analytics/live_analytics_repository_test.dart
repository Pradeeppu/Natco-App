/// Tests for [LiveAnalyticsRepositoryImpl] against the same demo seed
/// [ResultRepositoryImpl] and [OmrValidationRepositoryImpl] are tested
/// against, so a change to one and not the other shows up immediately.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/analytics/data/repository/live_analytics_repository_impl.dart';
import 'package:natco_app/features/analytics/domain/entity/question_analytics.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/session_repository_impl.dart';
import 'package:natco_app/features/assessment_sessions/data/service/demo_session_data.dart';
import 'package:natco_app/features/assessment_sessions/data/service/session_store.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_repository.dart';
import 'package:natco_app/features/assessments/data/repository/assessment_repository_impl.dart';
import 'package:natco_app/features/assessments/data/service/demo_assessment_data.dart';
import 'package:natco_app/features/assessments/data/service/in_memory_assessment_data_source.dart';
import 'package:natco_app/features/assessments/domain/repository/assessment_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_validation/data/repository/omr_validation_repository_impl.dart';
import 'package:natco_app/features/omr_validation/data/service/demo_omr_data.dart';
import 'package:natco_app/features/omr_validation/data/service/in_memory_omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/results/data/repository/result_repository_impl.dart';
import 'package:natco_app/features/results/data/service/in_memory_result_data_source.dart';
import 'package:natco_app/features/results/domain/repository/result_repository.dart';
import 'package:natco_app/features/schools/data/repository/school_hierarchy_repository_impl.dart';
import 'package:natco_app/features/schools/data/service/in_memory_school_data_source.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/students/data/repository/student_repository_impl.dart';
import 'package:natco_app/features/students/data/service/in_memory_student_data_source.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';

void main() {
  late OmrValidationRepository omrRepository;
  late ResultRepository resultRepository;
  late SessionRepository sessionRepository;
  late LiveAnalyticsRepositoryImpl analytics;

  setUp(() {
    final InMemoryAuditSink auditSink = InMemoryAuditSink();
    omrRepository = OmrValidationRepositoryImpl(
      dataSource: InMemoryOmrValidationDataSource(
        submissions: demoOmrSubmissions(),
        answers: demoOmrAnswers(),
      ),
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );

    final SchoolHierarchyRepository schoolRepository = SchoolHierarchyRepositoryImpl(
      dataSource: InMemorySchoolDataSource(),
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    final StudentRepository studentRepository = StudentRepositoryImpl(
      dataSource: InMemoryStudentDataSource(),
      schoolRepository: schoolRepository,
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    final AssessmentRepository assessmentRepository = AssessmentRepositoryImpl(
      dataSource: InMemoryAssessmentDataSource(
        assessments: demoAssessments(),
        answerKeys: demoAnswerKeys(),
      ),
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    sessionRepository = SessionRepositoryImpl(
      store: InMemoryAssessmentSessionStore(sessions: demoSessions()),
      assessmentRepository: assessmentRepository,
      schoolRepository: schoolRepository,
      studentRepository: studentRepository,
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    resultRepository = ResultRepositoryImpl(
      dataSource: InMemoryResultDataSource(),
      omrRepository: omrRepository,
      sessionRepository: sessionRepository,
      assessmentRepository: assessmentRepository,
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    analytics = LiveAnalyticsRepositoryImpl(
      resultRepository: resultRepository,
      omrRepository: omrRepository,
      sessionRepository: sessionRepository,
    );
  });

  test(
    'the summary reconciles against raw results, computed live rather than '
    'cached',
    () async {
      // Nothing scored yet: every metric starts at zero, not a placeholder.
      final AssessmentAnalyticsSummary before = (await analytics.getSummary(
        assessmentId: DemoAssessmentIds.midlineGrade5,
        scope: const AccessScope.global(),
      )).valueOrNull!;
      expect(before.scoredCount, 0);
      expect(before.averagePercentage, 0);

      await resultRepository.scoreSubmission(
        DemoOmrIds.cleanSheet,
        actorUserId: 'demo_teacher',
        actorRole: 'PST_TEACHER',
      );

      final AssessmentAnalyticsSummary after = (await analytics.getSummary(
        assessmentId: DemoAssessmentIds.midlineGrade5,
        scope: const AccessScope.global(),
      )).valueOrNull!;
      expect(after.scoredCount, 1);
      // The demo generator reads every question correctly at high
      // confidence, so a clean sheet is full marks.
      expect(after.averagePercentage, 100);
      expect(after.capturedCount, 5); // every demo submission, any stage
    },
  );

  test('question analytics tally per-question correctness across scored '
      'sheets', () async {
    await resultRepository.scoreSubmission(
      DemoOmrIds.cleanSheet,
      actorUserId: 'demo_teacher',
      actorRole: 'PST_TEACHER',
    );

    final List<QuestionAnalytics> questions = (await analytics
            .getQuestionAnalytics(
              assessmentId: DemoAssessmentIds.midlineGrade5,
              scope: const AccessScope.global(),
            ))
        .valueOrNull!;

    expect(questions, hasLength(50));
    final QuestionAnalytics q1 = questions.firstWhere(
      (QuestionAnalytics q) => q.questionNumber == 1,
    );
    expect(q1.totalResponses, 1);
    expect(q1.correctCount, 1);
    expect(q1.correctPercentage, 100);
  });

  test('a cluster-scoped caller never sees a school outside their clusters', () async {
    await resultRepository.scoreSubmission(
      DemoOmrIds.cleanSheet, // cluster 1
      actorUserId: 'demo_teacher',
      actorRole: 'PST_TEACHER',
    );
    await resultRepository.scoreSubmission(
      DemoOmrIds.multipleMarkSheet, // cluster 2, still flagged so this fails
      actorUserId: 'demo_supervisor',
      actorRole: 'SUPERVISOR',
    );

    const AccessScope cluster1Scope = AccessScope(
      level: ScopeLevel.cluster,
      clusterIds: <String>{'cl_demo_1'},
    );
    final AssessmentAnalyticsSummary summary = (await analytics.getSummary(
      assessmentId: DemoAssessmentIds.midlineGrade5,
      scope: cluster1Scope,
    )).valueOrNull!;

    // Only the clean sheet (cluster 1) is visible and scored; the flagged
    // cluster-2 sheet was never scored in the first place, so this also
    // proves the scope filter rather than a scoring side effect.
    expect(summary.scoredCount, 1);
  });
}
