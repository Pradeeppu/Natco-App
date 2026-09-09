/// Seed data for demo mode: a handful of captured sheets spanning the states
/// the validation screens need to render — a clean high-confidence sheet
/// needing no one, and several sheets sitting in the queue for different
/// reasons (a genuinely ambiguous question, a faint mark, an erased answer,
/// a multiple mark).
///
/// Student ids are real `demoStudents()` entries, not invented names — the
/// screens resolve a display name by id through the real student repository,
/// exactly as they would against a live backend, so nothing here has to keep
/// a name in sync with the master-data generator by hand.
library;

import 'package:natco_app/features/assessment_sessions/data/service/demo_session_data.dart';
import 'package:natco_app/features/assessments/data/service/demo_assessment_data.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';

abstract final class DemoOmrIds {
  /// High confidence throughout; ready to score with nobody's attention.
  static const String cleanSheet = '0001820';

  /// The ambiguous case: Q17 is a genuine coin-flip between two options and
  /// the machine will not guess. Referenced by the layout and preview-
  /// labelling tests, so it stays this id rather than a fresh one.
  static const String ambiguousSheet = '0001827';

  static const String faintMarkSheet = '0001830';
  static const String erasedAnswerSheet = '0001791';
  static const String multipleMarkSheet = '0001842';
}

final DateTime _capturedAt = DateTime.utc(2026, 9, 15, 10, 40);

const String _cluster1 = DemoHierarchyIds.clusterId1;
const String _cluster2 = DemoHierarchyIds.clusterId2;
const String _district1 = DemoHierarchyIds.districtId1;
const String _state = DemoHierarchyIds.stateId;

List<OmrSubmission> demoOmrSubmissions() => <OmrSubmission>[
  _submission(
    omrId: DemoOmrIds.cleanSheet,
    studentId: 'stu_demo_001',
    schoolId: DemoHierarchyIds.schoolId1,
    clusterId: _cluster1,
    validationStatus: ValidationStatus.notRequired,
    processingStatus: OmrProcessingStatus.processed,
  ),
  _submission(
    omrId: DemoOmrIds.ambiguousSheet,
    studentId: 'stu_demo_002',
    schoolId: DemoHierarchyIds.schoolId1,
    clusterId: _cluster1,
    validationStatus: ValidationStatus.pending,
    processingStatus: OmrProcessingStatus.needsValidation,
  ),
  _submission(
    omrId: DemoOmrIds.faintMarkSheet,
    studentId: 'stu_demo_010',
    schoolId: DemoHierarchyIds.schoolId1,
    clusterId: _cluster1,
    validationStatus: ValidationStatus.pending,
    processingStatus: OmrProcessingStatus.needsValidation,
  ),
  _submission(
    omrId: DemoOmrIds.erasedAnswerSheet,
    studentId: 'stu_demo_025',
    schoolId: DemoHierarchyIds.schoolId2,
    clusterId: _cluster1,
    validationStatus: ValidationStatus.pending,
    processingStatus: OmrProcessingStatus.needsValidation,
  ),
  _submission(
    omrId: DemoOmrIds.multipleMarkSheet,
    studentId: 'stu_demo_045',
    schoolId: DemoHierarchyIds.schoolId3,
    clusterId: _cluster2,
    validationStatus: ValidationStatus.pending,
    processingStatus: OmrProcessingStatus.needsValidation,
  ),
];

OmrSubmission _submission({
  required String omrId,
  required String studentId,
  required String schoolId,
  required String clusterId,
  required ValidationStatus validationStatus,
  required OmrProcessingStatus processingStatus,
}) => OmrSubmission(
  omrId: omrId,
  submissionId: 'sub_demo_$omrId',
  sessionId: DemoSessionIds.inProgress,
  assessmentId: DemoAssessmentIds.midlineGrade5,
  studentId: studentId,
  schoolId: schoolId,
  clusterId: clusterId,
  districtId: _district1,
  stateId: _state,
  capturedBy: 'demo_teacher',
  capturedAt: _capturedAt,
  deviceId: 'demo-device',
  originalImagePath: '/demo/omr/$omrId.jpg',
  processedImagePath: '/demo/omr/${omrId}_aligned.jpg',
  imageQuality: const ImageQualityReport(
    blurScore: 0.86,
    brightnessScore: 0.79,
    contrastScore: 0.81,
    resolutionPx: 3024000,
    sheetDetected: true,
    markersDetected: 4,
    rotationDegrees: 0.6,
    perspectiveSkew: 0.02,
    verdict: QualityVerdict.pass,
  ),
  processingStatus: processingStatus,
  validationStatus: validationStatus,
  answerKeyVersion: 1,
  createdAt: _capturedAt,
  updatedAt: _capturedAt.add(const Duration(minutes: 3)),
);

/// Fifty answers per submission, deterministic so a demo re-run scores
/// identically. The default reads every question correctly against
/// `demoAnswerKeys()`'s v1 key (`A,B,C,D` cycling) at high confidence; each
/// submission overrides the one or two questions that put it in the queue.
List<OmrAnswer> demoOmrAnswers() => <OmrAnswer>[
  ...omrAnswersFor(DemoOmrIds.cleanSheet, total: 50),
  ...omrAnswersFor(
    DemoOmrIds.ambiguousSheet,
    total: 50,
    overrides: <int, OmrAnswer Function(OmrAnswer base)>{
      // Two bubbles nearly equally dark — exactly what must not be
      // auto-resolved. The correct option per the key is A; a validator who
      // reads the sheet and picks B is recording a real disagreement, not a
      // typo, and scoring will mark it wrong once it runs.
      17: (OmrAnswer base) => base._withReading(
        optionScores: const <String, double>{
          'A': 0.72,
          'B': 0.69,
          'C': 0.10,
          'D': 0.08,
        },
        machineAnswer: null,
        machineConfidence: 0.34,
        machineStatus: DetectionStatus.mediumConfidence,
      ),
    },
  ),
  ...omrAnswersFor(
    DemoOmrIds.faintMarkSheet,
    total: 50,
    overrides: <int, OmrAnswer Function(OmrAnswer base)>{
      4: (OmrAnswer base) => base._withReading(
        optionScores: const <String, double>{
          'A': 0.03,
          'B': 0.05,
          'C': 0.31,
          'D': 0.02,
        },
        machineAnswer: 'C',
        machineConfidence: 0.41,
        machineStatus: DetectionStatus.mediumConfidence,
      ),
    },
  ),
  ...omrAnswersFor(
    DemoOmrIds.erasedAnswerSheet,
    total: 50,
    overrides: <int, OmrAnswer Function(OmrAnswer base)>{
      22: (OmrAnswer base) => base._withReading(
        optionScores: const <String, double>{
          'A': 0.22,
          'B': 0.19,
          'C': 0.05,
          'D': 0.04,
        },
        machineAnswer: null,
        machineConfidence: 0.28,
        machineStatus: DetectionStatus.lowConfidence,
      ),
      23: (OmrAnswer base) => base._withReading(
        optionScores: const <String, double>{
          'A': 0.18,
          'B': 0.04,
          'C': 0.21,
          'D': 0.03,
        },
        machineAnswer: null,
        machineConfidence: 0.31,
        machineStatus: DetectionStatus.lowConfidence,
      ),
    },
  ),
  ...omrAnswersFor(
    DemoOmrIds.multipleMarkSheet,
    total: 50,
    overrides: <int, OmrAnswer Function(OmrAnswer base)>{
      17: (OmrAnswer base) => base._withReading(
        optionScores: const <String, double>{
          'A': 0.61,
          'B': 0.58,
          'C': 0.55,
          'D': 0.06,
        },
        machineAnswer: null,
        machineConfidence: 0.22,
        machineStatus: DetectionStatus.multipleMark,
      ),
    },
  ),
];

/// Builds [total] high-confidence, correctly-read answers for [omrId], then
/// applies [overrides] by question number. Exposed (not private) so
/// `test/features/omr_validation` can build additional scenarios without
/// duplicating the base-answer boilerplate.
List<OmrAnswer> omrAnswersFor(
  String omrId, {
  required int total,
  Map<int, OmrAnswer Function(OmrAnswer base)> overrides = const {},
}) {
  final List<OmrAnswer> answers = <OmrAnswer>[];
  for (int q = 1; q <= total; q++) {
    // Matches `demoAnswerKeys()`'s v1 key exactly: `correctOption:
    // kAnswerOptions[(q - 1) % 4]`. Kept in step by using the same options
    // list and the same formula rather than a copy of the answers.
    final String correct = kAnswerOptions[(q - 1) % 4];
    OmrAnswer answer = OmrAnswer(
      omrAnswerId: '${omrId}_q$q',
      omrId: omrId,
      questionNumber: q,
      optionScores: <String, double>{
        for (final String option in kAnswerOptions)
          option: option == correct ? 0.88 : 0.04,
      },
      machineAnswer: correct,
      machineConfidence: 0.88,
      machineStatus: DetectionStatus.highConfidence,
      finalAnswer: correct,
      finalAnswerSource: AnswerSource.machine,
      bubbleCropPath: '/demo/omr/crops/${omrId}_q$q.jpg',
    );
    final OmrAnswer Function(OmrAnswer base)? override = overrides[q];
    if (override != null) {
      answer = override(answer);
    }
    answers.add(answer);
  }
  return answers;
}

extension on OmrAnswer {
  /// Rebuilds this seed answer with a different machine reading, leaving the
  /// final-answer bookkeeping matching a fresh, not-yet-validated state — the
  /// same shape a real detection pass would produce.
  OmrAnswer _withReading({
    required Map<String, double> optionScores,
    required String? machineAnswer,
    required double machineConfidence,
    required DetectionStatus machineStatus,
  }) => OmrAnswer(
    omrAnswerId: omrAnswerId,
    omrId: omrId,
    questionNumber: questionNumber,
    optionScores: optionScores,
    machineAnswer: machineAnswer,
    machineConfidence: machineConfidence,
    machineStatus: machineStatus,
    // Not yet decided: the flagged answer's `finalAnswer` starts unset, and
    // `OmrValidationPolicy.isFullyValidated` reads exactly that to mean "this
    // submission still needs a person".
    finalAnswer: null,
    finalAnswerSource: AnswerSource.machine,
    bubbleCropPath: bubbleCropPath,
  );
}
