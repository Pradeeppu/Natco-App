/// Tests for [InMemoryOmrSubmissionsRepository]: creation, the quality-gate
/// override transition, and scope isolation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_capture/data/repository/in_memory_omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/quality_override.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';

void main() {
  late InMemoryOmrSubmissionsRepository repo;
  final Clock clock = FixedClock(DateTime.utc(2026, 9, 11));

  const ImageQualityReport passingReport = ImageQualityReport(
    blurScore: 0.9,
    brightnessScore: 0.5,
    contrastScore: 0.5,
    shadowDeviation: 0.05,
    verdict: ImageQualityVerdict.pass,
    failureReasons: <String>[],
  );
  const ImageQualityReport failingReport = ImageQualityReport(
    blurScore: 0.05,
    brightnessScore: 0.5,
    contrastScore: 0.5,
    shadowDeviation: 0.05,
    verdict: ImageQualityVerdict.fail,
    failureReasons: <String>['The photo is blurred. Hold the phone steady and retake.'],
  );

  OmrSubmission buildSubmission({
    required String submissionId,
    required String schoolId,
    required String clusterId,
    required String districtId,
    required String stateId,
    OmrProcessingStatus status = OmrProcessingStatus.qualityChecked,
    ImageQualityReport report = passingReport,
  }) {
    final DateTime now = clock.nowUtc();
    return OmrSubmission(
      submissionId: submissionId,
      omrId: '0001827',
      sessionId: 'session-1',
      assessmentId: 'assessment-1',
      studentId: 'student-1',
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      capturedBy: 'teacher-1',
      capturedAt: now,
      deviceId: 'device-1',
      originalImagePath: '/tmp/$submissionId.jpg',
      imageQuality: report,
      processingStatus: status,
      validationStatus: ValidationStatus.notRequired,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    repo = InMemoryOmrSubmissionsRepository(clock: clock);
  });

  test('creates and retrieves a submission', () async {
    final submission = buildSubmission(
      submissionId: 'sub-1',
      schoolId: 'sch1',
      clusterId: 'cl1',
      districtId: 'di1',
      stateId: 'st1',
    );
    await repo.createSubmission(submission);

    final fetched = await repo.getSubmission('sub-1');
    expect(fetched.valueOrNull?.submissionId, 'sub-1');

    final forSession = await repo.listForSession('session-1');
    expect(forSession.valueOrNull, hasLength(1));
  });

  test('overrideQualityGate moves a failed submission back to quality-checked', () async {
    final submission = buildSubmission(
      submissionId: 'sub-1',
      schoolId: 'sch1',
      clusterId: 'cl1',
      districtId: 'di1',
      stateId: 'st1',
      status: OmrProcessingStatus.qualityFailed,
      report: failingReport,
    );
    await repo.createSubmission(submission);

    final override = QualityOverride(
      overriddenBy: 'supervisor-1',
      reason: 'Best available copy; original sheet was damaged.',
      overriddenAt: clock.nowUtc(),
    );
    final result = await repo.overrideQualityGate('sub-1', override);
    expect(result.valueOrNull?.processingStatus, OmrProcessingStatus.qualityChecked);
    expect(result.valueOrNull?.qualityOverride?.reason, override.reason);
  });

  test('overrideQualityGate refuses a submission that is not quality-failed', () async {
    final submission = buildSubmission(
      submissionId: 'sub-1',
      schoolId: 'sch1',
      clusterId: 'cl1',
      districtId: 'di1',
      stateId: 'st1',
    );
    await repo.createSubmission(submission);

    final result = await repo.overrideQualityGate(
      'sub-1',
      QualityOverride(
        overriddenBy: 'supervisor-1',
        reason: 'not applicable',
        overriddenAt: clock.nowUtc(),
      ),
    );
    expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
  });

  test('a cluster-scoped caller only sees submissions at their schools', () async {
    await repo.createSubmission(
      buildSubmission(
        submissionId: 'sub-a',
        schoolId: 'schA',
        clusterId: 'clA',
        districtId: 'diA',
        stateId: 'stA',
      ),
    );
    await repo.createSubmission(
      buildSubmission(
        submissionId: 'sub-b',
        schoolId: 'schB',
        clusterId: 'clB',
        districtId: 'diA',
        stateId: 'stA',
      ),
    );

    final scopedToA = AccessScope.singleSchool('schA');
    final forA = await repo.listInScope(scopedToA);
    expect(forA.valueOrNull, hasLength(1));
    expect(forA.valueOrNull!.single.schoolId, 'schA');

    final global = await repo.listInScope(const AccessScope.global());
    expect(global.valueOrNull, hasLength(2));
  });
}
