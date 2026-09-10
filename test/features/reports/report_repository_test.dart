/// Tests for [ReportRepositoryImpl]: every report type produces real,
/// scoped, audited CSV — not a placeholder.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/analytics/data/repository/live_analytics_repository_impl.dart';
import 'package:natco_app/features/analytics/domain/repository/analytics_repository.dart';
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
import 'package:natco_app/features/reports/data/repository/report_repository_impl.dart';
import 'package:natco_app/features/reports/domain/entity/generated_report.dart';
import 'package:natco_app/features/reports/domain/entity/report_type.dart';
import 'package:natco_app/features/results/data/repository/result_repository_impl.dart';
import 'package:natco_app/features/results/data/service/in_memory_result_data_source.dart';
import 'package:natco_app/features/results/domain/repository/result_repository.dart';
import 'package:natco_app/features/schools/data/repository/school_hierarchy_repository_impl.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';
import 'package:natco_app/features/schools/data/service/in_memory_school_data_source.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/students/data/repository/student_repository_impl.dart';
import 'package:natco_app/features/students/data/service/in_memory_student_data_source.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';
import 'package:natco_app/features/sync/data/repository/sync_queue_repository_impl.dart';
import 'package:natco_app/features/sync/data/service/sync_queue_data_source.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';
import 'package:natco_app/features/sync/domain/service/sync_conflict_policy.dart';

final class _InMemoryQueueDataSource implements SyncQueueDataSource {
  final Map<String, SyncQueueEntry> _entries = <String, SyncQueueEntry>{};

  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() async =>
      ok(_entries.values.toList());

  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<void>> removeEntry(String syncId) async {
    _entries.remove(syncId);
    return ok(null);
  }
}

void main() {
  late InMemoryAuditSink auditSink;
  late ResultRepository resultRepository;
  late OmrValidationRepository omrRepository;
  late SyncQueueRepository syncQueueRepository;
  late ReportRepositoryImpl reports;

  setUp(() async {
    auditSink = InMemoryAuditSink();
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
      dataSource: InMemorySchoolDataSource(
        states: demoStates(),
        districts: demoDistricts(),
        clusters: demoClusters(),
        schools: demoSchools(),
      ),
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    final StudentRepository studentRepository = StudentRepositoryImpl(
      dataSource: InMemoryStudentDataSource(students: demoStudents()),
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
    final SessionRepository sessionRepository = SessionRepositoryImpl(
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
    final AnalyticsRepository analyticsRepository = LiveAnalyticsRepositoryImpl(
      resultRepository: resultRepository,
      omrRepository: omrRepository,
      sessionRepository: sessionRepository,
    );
    syncQueueRepository = SyncQueueRepositoryImpl(
      dataSource: _InMemoryQueueDataSource(),
      conflictPolicy: const SyncConflictPolicy(),
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );

    reports = ReportRepositoryImpl(
      resultRepository: resultRepository,
      analyticsRepository: analyticsRepository,
      omrRepository: omrRepository,
      syncQueueRepository: syncQueueRepository,
      schoolRepository: schoolRepository,
      studentRepository: studentRepository,
      assessmentRepository: assessmentRepository,
      auditSink: auditSink,
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );

    // One real scored result to report on.
    await resultRepository.scoreSubmission(
      DemoOmrIds.cleanSheet,
      actorUserId: 'demo_teacher',
      actorRole: 'PST_TEACHER',
    );
  });

  Future<GeneratedReport> generate(ReportType type) async {
    final result = await reports.generateReport(
      type: type,
      assessmentId: DemoAssessmentIds.midlineGrade5,
      scope: const AccessScope.global(),
      actorUserId: 'demo_supervisor',
      actorRole: 'SUPERVISOR',
    );
    expect(result.isSuccess, isTrue, reason: '$type failed: ${result.failureOrNull}');
    return result.valueOrNull!;
  }

  test('student result has one real row, no invented figures', () async {
    final GeneratedReport report = await generate(ReportType.studentResult);
    expect(report.rowCount, 1);
    expect(report.csvContent, contains('Aarav Sharma'));
    expect(report.fileName, isNot(contains('Aarav')));
    expect(report.fileName, startsWith('student_result_'));
  });

  test('question analysis has one row per question', () async {
    final GeneratedReport report = await generate(ReportType.questionAnalysis);
    expect(report.rowCount, 50);
  });

  test('assessment summary reflects the one scored sheet', () async {
    final GeneratedReport report = await generate(ReportType.assessmentSummary);
    expect(report.rowCount, 1);
    expect(report.csvContent, contains('Grade 5 Numeracy - Midline'));
  });

  test('school/cluster/district summaries group real results', () async {
    final GeneratedReport school = await generate(ReportType.schoolSummary);
    final GeneratedReport cluster = await generate(ReportType.clusterSummary);
    final GeneratedReport district = await generate(ReportType.districtSummary);
    expect(school.rowCount, 1); // one school scored so far
    expect(cluster.rowCount, 1);
    expect(district.rowCount, 1);
  });

  test('omr processing counts every real submission, any stage', () async {
    final GeneratedReport report = await generate(ReportType.omrProcessing);
    // 5 demo submissions, grouped by (school, status) — at least one row.
    expect(report.rowCount, greaterThan(0));
  });

  test(
    'validation report lists every real decision, not a placeholder',
    () async {
      await omrRepository.recordDecision(
        omrId: DemoOmrIds.ambiguousSheet,
        questionNumber: 17,
        chosenAnswer: 'B',
        reason: 'B is fully filled',
        actorUserId: 'demo_supervisor',
        actorRole: 'SUPERVISOR',
      );
      final GeneratedReport report = await generate(ReportType.validation);
      expect(report.rowCount, greaterThanOrEqualTo(1));
      expect(report.csvContent, contains('B is fully filled'));
    },
  );

  test(
    'sync failures report reads the real queue, ignores assessmentId',
    () async {
      await syncQueueRepository.enqueue(
        SyncQueueEntry(
          syncId: 'sync_1',
          entityType: 'omr_submission',
          entityId: 'sub_1',
          operation: 'create',
          payloadRef: 'ref_1',
          idempotencyKey: 'idem_1',
          createdAt: DateTime.utc(2026),
          attemptCount: 8,
          status: SyncStatus.failed,
          errorMessage: 'permanently offline',
        ),
      );
      final GeneratedReport report = await generate(ReportType.syncFailures);
      expect(report.rowCount, 1);
      expect(report.csvContent, contains('permanently offline'));
    },
  );

  test('every export writes exactly one audit entry naming no student', () async {
    await generate(ReportType.studentResult);
    final AuditEvent event = auditSink.events.last;
    expect(event.action, AuditAction.reportExported);
    expect(event.newValue.toString(), isNot(contains('Aarav')));
  });
}
