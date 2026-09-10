/// The single [ReportRepository] implementation.
///
/// Composes every repository a report needs to read from — results,
/// analytics, OMR submissions and validation history, the sync queue, the
/// school hierarchy and student master data for display names — and writes
/// one audit entry per export. Nothing here writes a score, a validation
/// decision or any other domain state; every method is a read followed by a
/// CSV encode.
library;

import 'package:csv/csv.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/analytics/domain/entity/question_analytics.dart';
import 'package:natco_app/features/analytics/domain/repository/analytics_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/repository/assessment_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/reports/domain/entity/generated_report.dart';
import 'package:natco_app/features/reports/domain/entity/report_type.dart';
import 'package:natco_app/features/reports/domain/repository/report_repository.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';
import 'package:natco_app/features/results/domain/repository/result_repository.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';

/// Large enough to return every row in one page for the master-data scale
/// this app targets (docs/02-data-model.md: hundreds of schools per state,
/// not tens of thousands). A deployment past that scale needs the same
/// server-side rollup docs/02 §7 already calls for on `QuestionAnalytics`,
/// not a bigger page size.
const int _kReportLookupPageSize = 5000;

final class ReportRepositoryImpl implements ReportRepository {
  ReportRepositoryImpl({
    required ResultRepository resultRepository,
    required AnalyticsRepository analyticsRepository,
    required OmrValidationRepository omrRepository,
    required SyncQueueRepository syncQueueRepository,
    required SchoolHierarchyRepository schoolRepository,
    required StudentRepository studentRepository,
    required AssessmentRepository assessmentRepository,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _resultRepository = resultRepository,
       _analyticsRepository = analyticsRepository,
       _omrRepository = omrRepository,
       _syncQueueRepository = syncQueueRepository,
       _schoolRepository = schoolRepository,
       _studentRepository = studentRepository,
       _assessmentRepository = assessmentRepository,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final ResultRepository _resultRepository;
  final AnalyticsRepository _analyticsRepository;
  final OmrValidationRepository _omrRepository;
  final SyncQueueRepository _syncQueueRepository;
  final SchoolHierarchyRepository _schoolRepository;
  final StudentRepository _studentRepository;
  final AssessmentRepository _assessmentRepository;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<GeneratedReport>> generateReport({
    required ReportType type,
    required String assessmentId,
    required AccessScope scope,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<List<List<Object?>>> rowsResult = await switch (type) {
      ReportType.studentResult => _studentResultRows(assessmentId, scope),
      ReportType.schoolSummary => _scopeSummaryRows(
        assessmentId,
        scope,
        groupBy: _GroupLevel.school,
      ),
      ReportType.clusterSummary => _scopeSummaryRows(
        assessmentId,
        scope,
        groupBy: _GroupLevel.cluster,
      ),
      ReportType.districtSummary => _scopeSummaryRows(
        assessmentId,
        scope,
        groupBy: _GroupLevel.district,
      ),
      ReportType.assessmentSummary => _assessmentSummaryRows(assessmentId, scope),
      ReportType.questionAnalysis => _questionAnalysisRows(assessmentId, scope),
      ReportType.omrProcessing => _omrProcessingRows(assessmentId, scope),
      ReportType.validation => _validationRows(assessmentId, scope),
      ReportType.syncFailures => _syncFailureRows(),
    };
    if (rowsResult.isFailure) {
      return err(rowsResult.failureOrNull!);
    }
    final List<List<Object?>> rows = rowsResult.valueOrNull!;
    final List<Object?> header = rows.first;
    final int dataRowCount = rows.length - 1;

    final DateTime now = _clock.nowUtc();
    final String csvContent = Csv().encode(rows);
    final String fileName =
        '${type.wireName.toLowerCase()}_'
        '${now.toIso8601String().replaceAll(RegExp('[:.]'), '-')}.csv';

    final GeneratedReport report = GeneratedReport(
      type: type,
      fileName: fileName,
      csvContent: csvContent,
      rowCount: dataRowCount,
      generatedAt: now,
    );

    await _auditSink.record(
      AuditEvent(
        auditId: _idGenerator.newId(),
        userId: actorUserId,
        role: actorRole,
        action: AuditAction.reportExported,
        entityType: 'report',
        entityId: type.wireName,
        timestamp: now,
        deviceId: _deviceInfo.deviceId,
        appVersion: _deviceInfo.appVersion,
        // Row count and column names only — never a value from a row, which
        // is exactly where a student's name could otherwise leak into the
        // audit log (requirement §35).
        newValue: <String, Object?>{
          'assessmentId': assessmentId,
          'scopeLevel': scope.level.wireName,
          'rowCount': dataRowCount,
          'columns': header,
        },
      ),
    );

    return ok(report);
  }

  // ------------------------------------------------------------- student result

  Future<Result<List<List<Object?>>>> _studentResultRows(
    String assessmentId,
    AccessScope scope,
  ) async {
    final Result<List<AssessmentResult>> resultsResult = await _allResults(
      assessmentId,
      scope,
    );
    if (resultsResult.isFailure) {
      return err(resultsResult.failureOrNull!);
    }

    final List<List<Object?>> rows = <List<Object?>>[
      <String>[
        'Student name',
        'School',
        'Grade',
        'Section',
        'Marks obtained',
        'Total marks',
        'Percentage',
        'Correct',
        'Incorrect',
        'Blank',
        'Multiple',
      ],
    ];
    for (final AssessmentResult result in resultsResult.valueOrNull!) {
      final String studentName = await _studentName(result.studentId);
      final String schoolName = await _schoolName(result.schoolId);
      rows.add(<Object?>[
        studentName,
        schoolName,
        result.grade,
        result.section,
        result.marksObtained,
        result.totalMarks,
        result.percentage.toStringAsFixed(1),
        result.correctCount,
        result.incorrectCount,
        result.blankCount,
        result.multipleMarkCount,
      ]);
    }
    return ok(rows);
  }

  // -------------------------------------------------- school/cluster/district

  Future<Result<List<List<Object?>>>> _scopeSummaryRows(
    String assessmentId,
    AccessScope scope, {
    required _GroupLevel groupBy,
  }) async {
    final Result<List<AssessmentResult>> resultsResult = await _allResults(
      assessmentId,
      scope,
    );
    if (resultsResult.isFailure) {
      return err(resultsResult.failureOrNull!);
    }

    final Map<String, List<AssessmentResult>> grouped = <String, List<AssessmentResult>>{};
    for (final AssessmentResult result in resultsResult.valueOrNull!) {
      final String key = switch (groupBy) {
        _GroupLevel.school => result.schoolId,
        _GroupLevel.cluster => result.clusterId,
        _GroupLevel.district => result.districtId,
      };
      grouped.putIfAbsent(key, () => <AssessmentResult>[]).add(result);
    }

    final String groupLabel = switch (groupBy) {
      _GroupLevel.school => 'School',
      _GroupLevel.cluster => 'Cluster',
      _GroupLevel.district => 'District',
    };
    final List<List<Object?>> rows = <List<Object?>>[
      <String>[groupLabel, 'Scored', 'Average %', 'Highest %', 'Lowest %'],
    ];

    for (final MapEntry<String, List<AssessmentResult>> entry in grouped.entries) {
      final String name = await switch (groupBy) {
        _GroupLevel.school => _schoolName(entry.key),
        _GroupLevel.cluster => _clusterName(entry.key, scope),
        _GroupLevel.district => _districtName(entry.key, scope),
      };
      final List<double> pct = entry.value
          .map((AssessmentResult r) => r.percentage)
          .toList(growable: false);
      rows.add(<Object?>[
        name,
        entry.value.length,
        (pct.reduce((double a, double b) => a + b) / pct.length)
            .toStringAsFixed(1),
        pct.reduce((double a, double b) => a > b ? a : b).toStringAsFixed(1),
        pct.reduce((double a, double b) => a < b ? a : b).toStringAsFixed(1),
      ]);
    }
    return ok(rows);
  }

  // --------------------------------------------------------- assessment summary

  Future<Result<List<List<Object?>>>> _assessmentSummaryRows(
    String assessmentId,
    AccessScope scope,
  ) async {
    final Result<Assessment> assessmentResult = await _assessmentRepository
        .getAssessment(assessmentId);
    if (assessmentResult.isFailure) {
      return err(assessmentResult.failureOrNull!);
    }
    final Result<AssessmentAnalyticsSummary> summaryResult = await _analyticsRepository
        .getSummary(assessmentId: assessmentId, scope: scope);
    if (summaryResult.isFailure) {
      return err(summaryResult.failureOrNull!);
    }
    final Assessment assessment = assessmentResult.valueOrNull!;
    final AssessmentAnalyticsSummary summary = summaryResult.valueOrNull!;
    return ok(<List<Object?>>[
      <String>[
        'Assessment',
        'Subject',
        'Grade',
        'Scored',
        'Expected',
        'Completion %',
        'Average %',
        'Highest %',
        'Lowest %',
      ],
      <Object?>[
        assessment.assessmentName,
        assessment.subject,
        assessment.grade,
        summary.scoredCount,
        summary.expectedCount,
        summary.completionPercentage.toStringAsFixed(1),
        summary.averagePercentage.toStringAsFixed(1),
        summary.highestPercentage.toStringAsFixed(1),
        summary.lowestPercentage.toStringAsFixed(1),
      ],
    ]);
  }

  // --------------------------------------------------------- question analysis

  Future<Result<List<List<Object?>>>> _questionAnalysisRows(
    String assessmentId,
    AccessScope scope,
  ) async {
    final Result<List<QuestionAnalytics>> result = await _analyticsRepository
        .getQuestionAnalytics(assessmentId: assessmentId, scope: scope);
    if (result.isFailure) {
      return err(result.failureOrNull!);
    }
    final List<List<Object?>> rows = <List<Object?>>[
      <String>[
        'Question',
        'Responses',
        'Correct',
        'Incorrect',
        'Blank',
        'Multiple',
        'Correct %',
      ],
    ];
    for (final QuestionAnalytics q in result.valueOrNull!) {
      rows.add(<Object?>[
        q.questionNumber,
        q.totalResponses,
        q.correctCount,
        q.incorrectCount,
        q.blankCount,
        q.multipleMarkCount,
        q.correctPercentage.toStringAsFixed(1),
      ]);
    }
    return ok(rows);
  }

  // ------------------------------------------------------------- omr processing

  Future<Result<List<List<Object?>>>> _omrProcessingRows(
    String assessmentId,
    AccessScope scope,
  ) async {
    final Result<List<OmrSubmission>> submissionsResult = await _allSubmissions(
      assessmentId,
      scope,
    );
    if (submissionsResult.isFailure) {
      return err(submissionsResult.failureOrNull!);
    }
    final List<List<Object?>> rows = <List<Object?>>[
      <String>['School', 'Status', 'Count'],
    ];
    final Map<(String, String), int> tally = <(String, String), int>{};
    for (final OmrSubmission submission in submissionsResult.valueOrNull!) {
      final String schoolName = await _schoolName(submission.schoolId);
      final (String, String) key = (schoolName, submission.processingStatus.displayName);
      tally[key] = (tally[key] ?? 0) + 1;
    }
    for (final MapEntry<(String, String), int> entry in tally.entries) {
      rows.add(<Object?>[entry.key.$1, entry.key.$2, entry.value]);
    }
    return ok(rows);
  }

  // ----------------------------------------------------------------- validation

  Future<Result<List<List<Object?>>>> _validationRows(
    String assessmentId,
    AccessScope scope,
  ) async {
    final Result<List<OmrSubmission>> submissionsResult = await _allSubmissions(
      assessmentId,
      scope,
    );
    if (submissionsResult.isFailure) {
      return err(submissionsResult.failureOrNull!);
    }
    final List<List<Object?>> rows = <List<Object?>>[
      <String>[
        'OMR ID',
        'Question',
        'Machine reading',
        'Confidence',
        'Final decision',
        'Validator',
        'Validated at (UTC)',
        'Reason',
      ],
    ];
    for (final OmrSubmission submission in submissionsResult.valueOrNull!) {
      final Result<List<OmrValidationRecord>> historyResult = await _omrRepository
          .getValidationHistory(submission.omrId);
      if (historyResult.isFailure) {
        continue;
      }
      for (final OmrValidationRecord record in historyResult.valueOrNull!) {
        rows.add(<Object?>[
          record.omrId,
          record.questionNumber,
          record.machineAnswer ?? 'Blank',
          record.machineConfidence.toStringAsFixed(2),
          record.chosenAnswer,
          record.validatorUserId,
          record.validatedAt.toIso8601String(),
          record.reason ?? '',
        ]);
      }
    }
    return ok(rows);
  }

  // -------------------------------------------------------------- sync failures

  /// Deliberately not scope-filtered: the sync queue is this device's own,
  /// not a remote collection with rows belonging to other people (the same
  /// reasoning `OmrValidationRepository.listCapturedOrProcessing` documents).
  Future<Result<List<List<Object?>>>> _syncFailureRows() async {
    final Result<List<SyncQueueEntry>> queueResult = await _syncQueueRepository
        .listQueue();
    if (queueResult.isFailure) {
      return err(queueResult.failureOrNull!);
    }
    final List<List<Object?>> rows = <List<Object?>>[
      <String>['Entity type', 'Entity ID', 'Operation', 'Attempts', 'Error'],
    ];
    for (final SyncQueueEntry entry in queueResult.valueOrNull!) {
      if (entry.status != SyncStatus.failed) {
        continue;
      }
      rows.add(<Object?>[
        entry.entityType,
        entry.entityId,
        entry.operation,
        entry.attemptCount,
        entry.errorMessage ?? '',
      ]);
    }
    return ok(rows);
  }

  // ------------------------------------------------------------------- helpers

  Future<Result<List<AssessmentResult>>> _allResults(
    String assessmentId,
    AccessScope scope,
  ) async {
    final List<AssessmentResult> all = <AssessmentResult>[];
    Object? cursor;
    while (true) {
      final Result<Page<AssessmentResult>> pageResult = await _resultRepository
          .listResults(
            assessmentId: assessmentId,
            scope: scope,
            cursor: cursor,
            pageSize: _kReportLookupPageSize,
          );
      if (pageResult.isFailure) {
        return err(pageResult.failureOrNull!);
      }
      final Page<AssessmentResult> page = pageResult.valueOrNull!;
      all.addAll(page.items);
      if (!page.hasMore) {
        break;
      }
      cursor = page.nextCursor;
    }
    return ok(all);
  }

  Future<Result<List<OmrSubmission>>> _allSubmissions(
    String assessmentId,
    AccessScope scope,
  ) async {
    final List<OmrSubmission> all = <OmrSubmission>[];
    Object? cursor;
    while (true) {
      final Result<Page<OmrSubmission>> pageResult = await _omrRepository
          .listSubmissionsForAssessment(
            assessmentId: assessmentId,
            scope: scope,
            cursor: cursor,
            pageSize: _kReportLookupPageSize,
          );
      if (pageResult.isFailure) {
        return err(pageResult.failureOrNull!);
      }
      final Page<OmrSubmission> page = pageResult.valueOrNull!;
      all.addAll(page.items);
      if (!page.hasMore) {
        break;
      }
      cursor = page.nextCursor;
    }
    return ok(all);
  }

  final Map<String, String> _schoolNameCache = <String, String>{};

  Future<String> _schoolName(String schoolId) async {
    final String? cached = _schoolNameCache[schoolId];
    if (cached != null) {
      return cached;
    }
    final Result<School> result = await _schoolRepository.getSchool(schoolId);
    final String name = result.valueOrNull?.schoolName ?? schoolId;
    _schoolNameCache[schoolId] = name;
    return name;
  }

  // `scope` is threaded through here rather than a hardcoded
  // `AccessScope.global()`: the grouping keys these look up already came
  // from properly scope-filtered results, but a name lookup with no scope
  // of its own would still be a real widening in demo mode, where scope
  // filtering is enforced in this same client code rather than by a
  // separate server rule. Cached per report generation, not across calls —
  // this repository is long-lived but the caller's scope is not.
  Map<String, String>? _clusterNameCache;

  Future<String> _clusterName(String clusterId, AccessScope scope) async {
    if (_clusterNameCache == null) {
      final Result<Page<Cluster>> result = await _schoolRepository.listClusters(
        scope: scope,
        pageSize: _kReportLookupPageSize,
      );
      _clusterNameCache = <String, String>{
        for (final Cluster c in result.valueOrNull?.items ?? const <Cluster>[])
          c.clusterId: c.clusterName,
      };
    }
    return _clusterNameCache![clusterId] ?? clusterId;
  }

  Map<String, String>? _districtNameCache;

  Future<String> _districtName(String districtId, AccessScope scope) async {
    if (_districtNameCache == null) {
      final Result<Page<District>> result = await _schoolRepository
          .listDistricts(scope: scope, pageSize: _kReportLookupPageSize);
      _districtNameCache = <String, String>{
        for (final District d in result.valueOrNull?.items ?? const <District>[])
          d.districtId: d.districtName,
      };
    }
    return _districtNameCache![districtId] ?? districtId;
  }

  final Map<String, String> _studentNameCache = <String, String>{};

  Future<String> _studentName(String studentId) async {
    final String? cached = _studentNameCache[studentId];
    if (cached != null) {
      return cached;
    }
    final Result<Student> result = await _studentRepository.getStudent(
      studentId,
    );
    final String name = result.valueOrNull?.studentName ?? studentId;
    _studentNameCache[studentId] = name;
    return name;
  }
}

enum _GroupLevel { school, cluster, district }
