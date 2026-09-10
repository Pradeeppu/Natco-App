/// End-to-end test for [OmrProcessingService]: a saved, quality-checked
/// submission goes in, and comes out `READY_FOR_SCORING` (or
/// `NEEDS_VALIDATION`) with its answers persisted — driven by a real
/// synthetic sheet through the real in-memory repositories, not mocks.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/omr_capture/data/repository/in_memory_omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/data/service/omr_image_store.dart';
import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';
import 'package:natco_app/features/omr_processing/data/repository/in_memory_omr_answers_repository.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processing_service.dart';

import '../../../tool/synthetic_omr_sheet.dart';

void main() {
  late OmrTemplate template;
  late Directory tempDir;
  const IdGenerator idGenerator = UuidIdGenerator();
  final Clock clock = FixedClock(DateTime.utc(2026, 9, 11));

  setUpAll(() {
    template = OmrTemplate.fromJsonString(
      File('assets/omr_templates/natco_v1.json').readAsStringSync(),
    );
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('natco_omr_processing_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  const ImageQualityReport passingQuality = ImageQualityReport(
    blurScore: 0.9,
    brightnessScore: 0.5,
    contrastScore: 0.8,
    shadowDeviation: 0.05,
    verdict: ImageQualityVerdict.pass,
    failureReasons: <String>[],
  );

  Future<
    ({
      InMemoryOmrSubmissionsRepository submissions,
      InMemoryOmrAnswersRepository answers,
      OmrProcessingService service,
      String submissionId,
    })
  >
  seed(Map<int, List<int>> filledOptions) async {
    final submissions = InMemoryOmrSubmissionsRepository(clock: clock);
    final answers = InMemoryOmrAnswersRepository();
    final imageStore = FileSystemOmrImageStore(rootDirectory: () async => tempDir);

    final sheet = renderSyntheticSheet(template, filledOptions: filledOptions);
    final Uint8List bytes = Uint8List.fromList(img.encodeJpg(sheet.image, quality: 92));
    final submissionId = idGenerator.newId();
    final writeResult = await imageStore.writeOriginal(
      submissionId: submissionId,
      bytes: bytes,
    );

    final DateTime now = clock.nowUtc();
    final submission = OmrSubmission(
      submissionId: submissionId,
      omrId: '0001827',
      sessionId: 'session-1',
      assessmentId: 'assessment-1',
      studentId: 'student-1',
      schoolId: 'school-1',
      clusterId: 'cluster-1',
      districtId: 'district-1',
      stateId: 'state-1',
      capturedBy: 'teacher-1',
      capturedAt: now,
      deviceId: 'device-1',
      originalImagePath: writeResult.valueOrNull!,
      imageQuality: passingQuality,
      processingStatus: OmrProcessingStatus.qualityChecked,
      validationStatus: ValidationStatus.notRequired,
      createdAt: now,
      updatedAt: now,
    );
    await submissions.createSubmission(submission);

    final service = OmrProcessingService(
      submissions: submissions,
      answers: answers,
      imageStore: imageStore,
      idGenerator: idGenerator,
      template: template,
    );

    return (
      submissions: submissions,
      answers: answers,
      service: service,
      submissionId: submissionId,
    );
  }

  test('a clean sheet reaches READY_FOR_SCORING with its answers persisted', () async {
    final fixtures = await seed(<int, List<int>>{
      1: <int>[1], // B
      2: <int>[0], // A
    });

    final result = await fixtures.service.processSubmission(
      submissionId: fixtures.submissionId,
      questionCount: 2,
      thresholds: const ScannerThresholds(),
    );

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull!.needsValidation, isFalse);

    final updated = await fixtures.submissions.getSubmission(fixtures.submissionId);
    expect(updated.valueOrNull?.processingStatus, OmrProcessingStatus.readyForScoring);
    expect(updated.valueOrNull?.validationStatus, ValidationStatus.notRequired);

    final storedAnswers = await fixtures.answers.listForOmrId('0001827');
    expect(storedAnswers.valueOrNull, hasLength(2));
    expect(storedAnswers.valueOrNull![0].machineAnswer, 'B');
    expect(storedAnswers.valueOrNull![1].machineAnswer, 'A');
  });

  test('a multiple-mark answer routes the submission to NEEDS_VALIDATION', () async {
    final fixtures = await seed(<int, List<int>>{
      1: <int>[0, 2],
    });

    final result = await fixtures.service.processSubmission(
      submissionId: fixtures.submissionId,
      questionCount: 1,
      thresholds: const ScannerThresholds(),
    );

    expect(result.valueOrNull!.needsValidation, isTrue);
    final updated = await fixtures.submissions.getSubmission(fixtures.submissionId);
    expect(updated.valueOrNull?.processingStatus, OmrProcessingStatus.needsValidation);
    expect(updated.valueOrNull?.validationStatus, ValidationStatus.pending);
  });

  test('a sheet with no findable markers ends at PROCESSING_FAILED with no answers written', () async {
    final submissions = InMemoryOmrSubmissionsRepository(clock: clock);
    final answers = InMemoryOmrAnswersRepository();
    final imageStore = FileSystemOmrImageStore(rootDirectory: () async => tempDir);

    final img.Image blank = img.Image(width: 600, height: 800);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    final Uint8List bytes = Uint8List.fromList(img.encodeJpg(blank));
    final submissionId = idGenerator.newId();
    final writeResult = await imageStore.writeOriginal(
      submissionId: submissionId,
      bytes: bytes,
    );
    final DateTime now = clock.nowUtc();
    await submissions.createSubmission(
      OmrSubmission(
        submissionId: submissionId,
        omrId: '0001827',
        sessionId: 'session-1',
        assessmentId: 'assessment-1',
        studentId: 'student-1',
        schoolId: 'school-1',
        clusterId: 'cluster-1',
        districtId: 'district-1',
        stateId: 'state-1',
        capturedBy: 'teacher-1',
        capturedAt: now,
        deviceId: 'device-1',
        originalImagePath: writeResult.valueOrNull!,
        imageQuality: passingQuality,
        processingStatus: OmrProcessingStatus.qualityChecked,
        validationStatus: ValidationStatus.notRequired,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final service = OmrProcessingService(
      submissions: submissions,
      answers: answers,
      imageStore: imageStore,
      idGenerator: idGenerator,
      template: template,
    );
    final result = await service.processSubmission(
      submissionId: submissionId,
      questionCount: 1,
      thresholds: const ScannerThresholds(),
    );

    expect(result.isFailure, isTrue);
    final updated = await submissions.getSubmission(submissionId);
    expect(updated.valueOrNull?.processingStatus, OmrProcessingStatus.processingFailed);
    final storedAnswers = await answers.listForOmrId('0001827');
    expect(storedAnswers.valueOrNull, isEmpty);
  });
}
