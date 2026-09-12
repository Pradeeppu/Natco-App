/// Tests for [ResultRepositoryImpl] end to end against the demo seed data:
/// scoring a submission, re-scoring superseding rather than mutating, and
/// [ResultRepository.ensureScored] filling gaps without re-scoring what is
/// already scored.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/file_system_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
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
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';
import 'package:natco_app/features/schools/data/repository/school_hierarchy_repository_impl.dart';
import 'package:natco_app/features/schools/data/service/in_memory_school_data_source.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/students/data/repository/student_repository_impl.dart';
import 'package:natco_app/features/students/data/service/in_memory_student_data_source.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';

import '../../dummy_sync.dart';

void main() {
  late InMemoryResultDataSource resultDataSource;
  late InMemoryOmrValidationDataSource omrDataSource;
  late OmrValidationRepository omrRepository;
  late SessionRepository sessionRepository;
  late AssessmentRepository assessmentRepository;
  late InMemoryAuditSink auditSink;
  late ResultRepositoryImpl repository;

  setUp(() {
    resultDataSource = InMemoryResultDataSource();
    omrDataSource = InMemoryOmrValidationDataSource(
      submissions: demoOmrSubmissions(),
      answers: demoOmrAnswers(),
    );
    auditSink = InMemoryAuditSink();
    omrRepository = OmrValidationRepositoryImpl(
      fileSystem: FakeFileSystemService(),
      syncQueue: DummySyncQueueRepository(),
      dataSource: omrDataSource,
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
    assessmentRepository = AssessmentRepositoryImpl(
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
      syncQueue: DummySyncQueueRepository(),
      store: InMemoryAssessmentSessionStore(sessions: demoSessions()),
      assessmentRepository: assessmentRepository,
      schoolRepository: schoolRepository,
      studentRepository: studentRepository,
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );

    repository = ResultRepositoryImpl(
      dataSource: resultDataSource,
      omrRepository: omrRepository,
      sessionRepository: sessionRepository,
      assessmentRepository: assessmentRepository,
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
  });

  group('scoreSubmission', () {
    test('refuses a sheet that still needs validation', () async {
      final Result<AssessmentResult> result = await repository.scoreSubmission(
        DemoOmrIds.ambiguousSheet,
        actorUserId: 'demo_teacher',
        actorRole: 'PST_TEACHER',
      );
      expect(result.isFailure, isTrue);
    });

    test('scores a clean, unflagged sheet', () async {
      final Result<AssessmentResult> result = await repository.scoreSubmission(
        DemoOmrIds.cleanSheet,
        actorUserId: 'demo_teacher',
        actorRole: 'PST_TEACHER',
      );
      expect(result.isSuccess, isTrue);
      final AssessmentResult value = result.valueOrNull!;
      expect(value.totalMarks, 50);
      // The demo answer generator reads every question correctly at high
      // confidence, so a clean sheet scores full marks.
      expect(value.marksObtained, 50);
      expect(value.correctCount, 50);
      expect(value.isSuperseded, isFalse);
      expect(auditSink.events.last.action, AuditAction.scoreGenerated);
    });

    test(
      'scoring the same submission twice supersedes rather than mutates',
      () async {
        final Result<AssessmentResult> first = await repository.scoreSubmission(
          DemoOmrIds.cleanSheet,
          actorUserId: 'demo_teacher',
          actorRole: 'PST_TEACHER',
        );
        final Result<AssessmentResult> second = await repository.scoreSubmission(
          DemoOmrIds.cleanSheet,
          actorUserId: 'demo_supervisor',
          actorRole: 'SUPERVISOR',
        );

        expect(first.valueOrNull!.resultId, isNot(second.valueOrNull!.resultId));
        expect(auditSink.events.last.action, AuditAction.scoreCorrected);

        // The first row now points at the second; its own scored fields are
        // untouched (Critical Rule 5) — only `supersededBy` changed.
        final Result<AssessmentResult?> reread = await resultDataSource
            .getCurrentResultForSubmission(DemoOmrIds.cleanSheet);
        expect(reread.valueOrNull!.resultId, second.valueOrNull!.resultId);
      },
    );

    test('scores a sheet once its last flagged answer is decided', () async {
      // Q4's correct option is 'D' (kAnswerOptions[(4-1)%4]); the validator
      // reading the sheet and confirming that is what makes this sheet
      // fully correct despite Q4 starting out flagged.
      await omrRepository.recordDecision(
        omrId: DemoOmrIds.faintMarkSheet,
        questionNumber: 4,
        chosenAnswer: 'D',
        actorUserId: 'demo_supervisor',
        actorRole: 'SUPERVISOR',
      );
      final Result<AssessmentResult> result = await repository.scoreSubmission(
        DemoOmrIds.faintMarkSheet,
        actorUserId: 'demo_supervisor',
        actorRole: 'SUPERVISOR',
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.correctCount, 50);
    });
  });

  group('ensureScored', () {
    test('scores every ready, not-yet-scored submission and skips the '
        'rest', () async {
      // Resolve every flagged answer across the demo sheets first, so every
      // submission in the seed becomes ready.
      await omrRepository.recordDecision(
        omrId: DemoOmrIds.faintMarkSheet,
        questionNumber: 4,
        chosenAnswer: 'C',
        actorUserId: 'demo_supervisor',
        actorRole: 'SUPERVISOR',
      );
      await omrRepository.recordDecision(
        omrId: DemoOmrIds.ambiguousSheet,
        questionNumber: 17,
        chosenAnswer: 'B',
        actorUserId: 'demo_supervisor',
        actorRole: 'SUPERVISOR',
      );

      final Result<int> first = await repository.ensureScored(
        assessmentId: DemoAssessmentIds.midlineGrade5,
        scope: const AccessScope.global(),
        actorUserId: 'demo_supervisor',
        actorRole: 'SUPERVISOR',
      );
      expect(first.isSuccess, isTrue);
      // Clean sheet, faint-mark sheet and now-resolved ambiguous sheet — all
      // three are on the midline assessment and now ready for scoring.
      expect(first.valueOrNull, 3);

      // A second sweep must not re-score what already has a current result.
      final Result<int> second = await repository.ensureScored(
        assessmentId: DemoAssessmentIds.midlineGrade5,
        scope: const AccessScope.global(),
        actorUserId: 'demo_supervisor',
        actorRole: 'SUPERVISOR',
      );
      expect(second.valueOrNull, 0);
    });
  });
}
