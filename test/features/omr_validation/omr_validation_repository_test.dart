/// Tests for [OmrValidationPolicy] and [OmrValidationRepositoryImpl] against
/// the in-memory data source and the demo seed data.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/data/repository/omr_validation_repository_impl.dart';
import 'package:natco_app/features/omr_validation/data/service/demo_omr_data.dart';
import 'package:natco_app/features/omr_validation/data/service/in_memory_omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';
import 'package:natco_app/features/omr_validation/domain/service/omr_validation_policy.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';

void main() {
  group('OmrValidationPolicy', () {
    test('choicesFor lists the four options plus Blank and Multiple', () {
      expect(OmrValidationPolicy.choicesFor(), <String>[
        'A',
        'B',
        'C',
        'D',
        'Blank',
        'Multiple',
      ]);
    });

    test('checkChoice rejects anything outside the fixed set', () {
      expect(OmrValidationPolicy.checkChoice('A'), isNull);
      expect(OmrValidationPolicy.checkChoice('Blank'), isNull);
      expect(OmrValidationPolicy.checkChoice('E'), isNotNull);
      expect(OmrValidationPolicy.checkChoice('blank'), isNotNull); // case-sensitive
    });

    test('isFullyValidated is true only once every flagged answer decided', () {
      final List<OmrAnswer> answers = omrAnswersFor('omr_x', total: 3);
      expect(OmrValidationPolicy.isFullyValidated(answers), isTrue);

      final List<OmrAnswer> withOneFlagged = <OmrAnswer>[
        answers[0],
        OmrAnswer(
          omrAnswerId: answers[1].omrAnswerId,
          omrId: answers[1].omrId,
          questionNumber: answers[1].questionNumber,
          optionScores: answers[1].optionScores,
          machineAnswer: null,
          machineConfidence: 0.3,
          machineStatus: DetectionStatus.lowConfidence,
          finalAnswer: null,
          finalAnswerSource: AnswerSource.machine,
        ),
        answers[2],
      ];
      expect(OmrValidationPolicy.isFullyValidated(withOneFlagged), isFalse);
    });
  });

  group('OmrValidationRepositoryImpl against the demo seed', () {
    late InMemoryOmrValidationDataSource dataSource;
    late InMemoryAuditSink auditSink;
    late OmrValidationRepositoryImpl repository;

    setUp(() {
      dataSource = InMemoryOmrValidationDataSource(
        submissions: demoOmrSubmissions(),
        answers: demoOmrAnswers(),
      );
      auditSink = InMemoryAuditSink();
      repository = OmrValidationRepositoryImpl(
        dataSource: dataSource,
        auditSink: auditSink,
        idGenerator: const UuidIdGenerator(),
        clock: const SystemClock(),
        deviceInfo: const StaticDeviceInfoService(),
      );
    });

    test('the queue lists only sheets with something flagged', () async {
      final Result<Page<OmrSubmission>> result = await repository.listQueue(
        scope: const AccessScope.global(),
      );
      final List<OmrSubmission> items = result.valueOrNull!.items;
      expect(items.map((OmrSubmission s) => s.omrId).toSet(), <String>{
        DemoOmrIds.ambiguousSheet,
        DemoOmrIds.faintMarkSheet,
        DemoOmrIds.erasedAnswerSheet,
        DemoOmrIds.multipleMarkSheet,
      });
      // The clean sheet needs nobody and must not appear.
      expect(
        items.any((OmrSubmission s) => s.omrId == DemoOmrIds.cleanSheet),
        isFalse,
      );
    });

    test('the queue is scope-filtered exactly like every other list', () async {
      const AccessScope clusterScope = AccessScope(
        level: ScopeLevel.cluster,
        clusterIds: <String>{DemoHierarchyIds.clusterId1},
      );
      final Result<Page<OmrSubmission>> result = await repository.listQueue(
        scope: clusterScope,
      );
      final List<OmrSubmission> items = result.valueOrNull!.items;
      // The multiple-mark sheet lives in cluster 2 and must not appear for a
      // cluster-1-scoped caller.
      expect(
        items.any((OmrSubmission s) => s.omrId == DemoOmrIds.multipleMarkSheet),
        isFalse,
      );
      expect(
        items.any((OmrSubmission s) => s.omrId == DemoOmrIds.ambiguousSheet),
        isTrue,
      );
    });

    test(
      'recordDecision writes a decision without touching machine evidence',
      () async {
        final Result<List<OmrAnswer>> beforeAnswers = await dataSource.getAnswers(
          DemoOmrIds.ambiguousSheet,
        );
        final OmrAnswer original = beforeAnswers.valueOrNull!.firstWhere(
          (OmrAnswer a) => a.questionNumber == 17,
        );

        final Result<OmrAnswer> result = await repository.recordDecision(
          omrId: DemoOmrIds.ambiguousSheet,
          questionNumber: 17,
          chosenAnswer: 'B',
          reason: 'B is fully filled, A is a smudge',
          actorUserId: 'demo_supervisor',
          actorRole: 'SUPERVISOR',
        );

        expect(result.isSuccess, isTrue);
        final OmrAnswer updated = result.valueOrNull!;
        expect(updated.finalAnswer, 'B');
        expect(updated.finalAnswerSource, AnswerSource.humanValidation);
        expect(updated.validatedBy, 'demo_supervisor');

        // Machine evidence is bit-for-bit unchanged.
        expect(updated.machineAnswer, original.machineAnswer);
        expect(updated.machineConfidence, original.machineConfidence);
        expect(updated.machineStatus, original.machineStatus);
        expect(updated.optionScores, original.optionScores);

        // An append-only record and an audit entry were both written.
        final Result<List<OmrValidationRecord>> history = await repository
            .getValidationHistory(DemoOmrIds.ambiguousSheet);
        expect(history.valueOrNull, hasLength(1));
        expect(auditSink.events, hasLength(1));
        expect(auditSink.events.single.action, AuditAction.omrValidated);
      },
    );

    test(
      'rejects a choice outside the fixed set before touching the answer',
      () async {
        final Result<OmrAnswer> result = await repository.recordDecision(
          omrId: DemoOmrIds.ambiguousSheet,
          questionNumber: 17,
          chosenAnswer: 'E',
          actorUserId: 'demo_supervisor',
          actorRole: 'SUPERVISOR',
        );
        expect(result.isFailure, isTrue);
        expect(auditSink.events, isEmpty);
      },
    );

    test(
      'a submission moves to validation-completed once its last flagged '
      'question is decided',
      () async {
        // The faint-mark sheet has exactly one flagged question (Q4).
        await repository.recordDecision(
          omrId: DemoOmrIds.faintMarkSheet,
          questionNumber: 4,
          chosenAnswer: 'C',
          actorUserId: 'demo_supervisor',
          actorRole: 'SUPERVISOR',
        );

        final Result<OmrSubmission> submission = await repository.getSubmission(
          DemoOmrIds.faintMarkSheet,
        );
        expect(
          submission.valueOrNull!.validationStatus,
          ValidationStatus.completed,
        );
        expect(submission.valueOrNull!.readyForScoring, isTrue);
      },
    );

    test(
      'a submission with two flagged questions stays pending after only one '
      'is decided',
      () async {
        // The erased-answer sheet has two flagged questions (Q22, Q23).
        await repository.recordDecision(
          omrId: DemoOmrIds.erasedAnswerSheet,
          questionNumber: 22,
          chosenAnswer: 'A',
          actorUserId: 'demo_supervisor',
          actorRole: 'SUPERVISOR',
        );

        final Result<OmrSubmission> submission = await repository.getSubmission(
          DemoOmrIds.erasedAnswerSheet,
        );
        expect(submission.valueOrNull!.needsValidation, isTrue);
        expect(submission.valueOrNull!.readyForScoring, isFalse);
      },
    );
  });
}
