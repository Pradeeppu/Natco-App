/// Tests for [InMemoryOmrAnswersRepository] and [HiveOmrAnswersRepository]:
/// creation, per-sheet listing, and — the durability half of Phase 6's
/// pipeline output — surviving a real Hive close and reopen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/features/omr_processing/data/repository/hive_omr_answers_repository.dart';
import 'package:natco_app/features/omr_processing/data/repository/in_memory_omr_answers_repository.dart';
import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';

void main() {
  OmrAnswer buildAnswer({
    required String omrAnswerId,
    required String omrId,
    required int questionNumber,
  }) => OmrAnswer(
    omrAnswerId: omrAnswerId,
    omrId: omrId,
    questionNumber: questionNumber,
    optionScores: <String, double>{'A': 0.05, 'B': 0.91, 'C': 0.06, 'D': 0.04},
    machineAnswer: 'B',
    machineConfidence: 0.87,
    machineStatus: DetectionStatus.highConfidence,
  );

  group('InMemoryOmrAnswersRepository', () {
    test('creates and lists answers for one sheet, sorted by question number', () async {
      final repo = InMemoryOmrAnswersRepository();
      await repo.createAnswers(<OmrAnswer>[
        buildAnswer(omrAnswerId: 'a2', omrId: '0001827', questionNumber: 2),
        buildAnswer(omrAnswerId: 'a1', omrId: '0001827', questionNumber: 1),
        buildAnswer(omrAnswerId: 'other', omrId: 'different-sheet', questionNumber: 1),
      ]);

      final result = await repo.listForOmrId('0001827');
      expect(result.valueOrNull, hasLength(2));
      expect(
        result.valueOrNull!.map((OmrAnswer a) => a.questionNumber),
        <int>[1, 2],
      );

      final single = await repo.getAnswer('a1');
      expect(single.valueOrNull?.machineAnswer, 'B');
    });
  });

  group('HiveOmrAnswersRepository durability', () {
    late Directory tempDir;
    final AppLogger logger = AppLogger(minimumLevel: LogLevel.error, sinks: const []);

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('natco_omr_answers_test_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('answers survive closing and reopening the Hive box', () async {
      final HiveOmrAnswersRepository beforeRestart = HiveOmrAnswersRepository(
        hive: Hive,
        logger: logger,
      );
      await beforeRestart.createAnswers(<OmrAnswer>[
        buildAnswer(omrAnswerId: 'a1', omrId: '0001827', questionNumber: 1),
        buildAnswer(omrAnswerId: 'a2', omrId: '0001827', questionNumber: 2),
      ]);

      await Hive.close();

      final HiveOmrAnswersRepository afterRestart = HiveOmrAnswersRepository(
        hive: Hive,
        logger: logger,
      );
      final result = await afterRestart.listForOmrId('0001827');
      expect(result.valueOrNull, hasLength(2));
      expect(result.valueOrNull!.first.machineAnswer, 'B');
    });
  });
}
