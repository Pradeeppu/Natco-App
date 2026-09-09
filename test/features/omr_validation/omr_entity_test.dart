/// Round-trip and invariant tests for the OMR processing/validation entities.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';

ImageQualityReport _quality({QualityVerdict verdict = QualityVerdict.pass}) =>
    ImageQualityReport(
      blurScore: 0.9,
      brightnessScore: 0.8,
      contrastScore: 0.8,
      resolutionPx: 3000000,
      sheetDetected: true,
      markersDetected: 4,
      rotationDegrees: 0.5,
      perspectiveSkew: 0.01,
      verdict: verdict,
    );

OmrAnswer _answer({
  String? machineAnswer = 'A',
  DetectionStatus status = DetectionStatus.highConfidence,
  String? finalAnswer,
  AnswerSource source = AnswerSource.machine,
}) => OmrAnswer(
  omrAnswerId: 'ans_1',
  omrId: 'omr_1',
  questionNumber: 1,
  optionScores: const <String, double>{'A': 0.9, 'B': 0.05},
  machineAnswer: machineAnswer,
  machineConfidence: 0.9,
  machineStatus: status,
  finalAnswer: finalAnswer ?? machineAnswer,
  finalAnswerSource: source,
);

void main() {
  group('ImageQualityReport', () {
    test('round-trips through JSON', () {
      final ImageQualityReport report = _quality();
      final ImageQualityReport decoded = ImageQualityReport.tryFromJson(
        report.toJson(),
      )!;
      expect(decoded, report);
    });

    test('canProcess is false only when the verdict is FAIL', () {
      expect(_quality(verdict: QualityVerdict.pass).canProcess, isTrue);
      expect(_quality(verdict: QualityVerdict.warn).canProcess, isTrue);
      expect(_quality(verdict: QualityVerdict.fail).canProcess, isFalse);
    });
  });

  group('DetectionStatus.isAutoAcceptable', () {
    test('only high confidence and blank are auto-acceptable', () {
      expect(DetectionStatus.highConfidence.isAutoAcceptable, isTrue);
      expect(DetectionStatus.blank.isAutoAcceptable, isTrue);
      expect(DetectionStatus.mediumConfidence.isAutoAcceptable, isFalse);
      expect(DetectionStatus.lowConfidence.isAutoAcceptable, isFalse);
      expect(DetectionStatus.multipleMark.isAutoAcceptable, isFalse);
      expect(DetectionStatus.unreadable.isAutoAcceptable, isFalse);
    });
  });

  group('OmrAnswer', () {
    test('round-trips through JSON', () {
      final OmrAnswer answer = _answer();
      expect(OmrAnswer.tryFromJson(answer.toJson()), answer);
    });

    test('needsValidation reflects the machine status', () {
      expect(_answer(status: DetectionStatus.highConfidence).needsValidation, isFalse);
      expect(_answer(status: DetectionStatus.mediumConfidence).needsValidation, isTrue);
    });

    test('withValidation changes only the human-decision fields', () {
      final OmrAnswer original = _answer(
        machineAnswer: null,
        status: DetectionStatus.multipleMark,
      );
      final DateTime now = DateTime.utc(2026, 9, 15, 12);
      final OmrAnswer validated = original.withValidation(
        finalAnswer: 'B',
        validatedBy: 'user_1',
        validatedAt: now,
        validationReason: 'clearly B',
      );

      // Every machine-evidence field is byte-for-byte unchanged.
      expect(validated.omrAnswerId, original.omrAnswerId);
      expect(validated.omrId, original.omrId);
      expect(validated.questionNumber, original.questionNumber);
      expect(validated.optionScores, original.optionScores);
      expect(validated.machineAnswer, original.machineAnswer);
      expect(validated.machineConfidence, original.machineConfidence);
      expect(validated.machineStatus, original.machineStatus);

      // Only the human-decision fields moved.
      expect(validated.finalAnswer, 'B');
      expect(validated.finalAnswerSource, AnswerSource.humanValidation);
      expect(validated.validatedBy, 'user_1');
      expect(validated.validatedAt, now);
      expect(validated.validationReason, 'clearly B');

      // Scoring fields are untouched by a validation write.
      expect(validated.isCorrect, isNull);
      expect(validated.marks, isNull);
    });

    test('withScore changes only the scoring fields', () {
      final OmrAnswer validated = _answer(
        finalAnswer: 'B',
        source: AnswerSource.humanValidation,
      );
      final OmrAnswer scored = validated.withScore(isCorrect: false, marks: 0);

      expect(scored.finalAnswer, validated.finalAnswer);
      expect(scored.finalAnswerSource, validated.finalAnswerSource);
      expect(scored.validatedBy, validated.validatedBy);
      expect(scored.isCorrect, isFalse);
      expect(scored.marks, 0);
    });
  });

  group('OmrProcessingStatus', () {
    test('is a one-way state machine', () {
      expect(
        OmrProcessingStatus.captured.canTransitionTo(OmrProcessingStatus.processing),
        isTrue,
      );
      expect(
        OmrProcessingStatus.scored.canTransitionTo(OmrProcessingStatus.captured),
        isFalse,
      );
      expect(OmrProcessingStatus.scored.allowedNext, isEmpty);
    });
  });

  group('OmrSubmission.readyForScoring', () {
    OmrSubmission submission({
      required OmrProcessingStatus processingStatus,
      required ValidationStatus validationStatus,
    }) => OmrSubmission(
      omrId: 'omr_1',
      submissionId: 'sub_1',
      sessionId: 'ses_1',
      assessmentId: 'as_1',
      schoolId: 'sch_1',
      clusterId: 'cl_1',
      districtId: 'di_1',
      stateId: 'st_1',
      capturedBy: 'user_1',
      capturedAt: DateTime.utc(2026, 9, 15),
      deviceId: 'device_1',
      originalImagePath: '/tmp/1.jpg',
      imageQuality: _quality(),
      processingStatus: processingStatus,
      validationStatus: validationStatus,
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    test('a processed sheet needing no validation is scorable', () {
      expect(
        submission(
          processingStatus: OmrProcessingStatus.processed,
          validationStatus: ValidationStatus.notRequired,
        ).readyForScoring,
        isTrue,
      );
    });

    test('a sheet still pending validation is not scorable', () {
      expect(
        submission(
          processingStatus: OmrProcessingStatus.needsValidation,
          validationStatus: ValidationStatus.pending,
        ).readyForScoring,
        isFalse,
      );
    });

    test('a sheet whose validation completed is scorable', () {
      expect(
        submission(
          processingStatus: OmrProcessingStatus.needsValidation,
          validationStatus: ValidationStatus.completed,
        ).readyForScoring,
        isTrue,
      );
    });

    test('a sheet that has not finished processing is not scorable', () {
      expect(
        submission(
          processingStatus: OmrProcessingStatus.captured,
          validationStatus: ValidationStatus.notRequired,
        ).readyForScoring,
        isFalse,
      );
    });
  });

  group('OmrValidationRecord', () {
    test('round-trips through JSON', () {
      final OmrValidationRecord record = OmrValidationRecord(
        validationId: 'val_1',
        omrId: 'omr_1',
        questionNumber: 17,
        machineAnswer: null,
        machineConfidence: 0.34,
        chosenAnswer: 'B',
        validatorUserId: 'user_1',
        validatedAt: DateTime.utc(2026, 9, 15, 12),
        deviceId: 'device_1',
        reason: 'clearly B',
      );
      expect(OmrValidationRecord.tryFromJson(record.toJson()), record);
    });
  });
}
