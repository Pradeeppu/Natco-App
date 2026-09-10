/// Hive-backed [OmrAnswersRepository].
///
/// Local-first for the same reason `HiveOmrSubmissionsRepository` is: the
/// engine has to be able to write its answers with no network, and each
/// write here is a single `Box.put` of the whole record.
library;

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/repository/omr_answers_repository.dart';

final class HiveOmrAnswersRepository implements OmrAnswersRepository {
  HiveOmrAnswersRepository({required HiveInterface hive, required AppLogger logger})
    : _hive = hive,
      _logger = logger;

  final HiveInterface _hive;
  final AppLogger _logger;

  @override
  Future<Result<List<OmrAnswer>>> listForOmrId(String omrId) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        final List<OmrAnswer> matches = <OmrAnswer>[
          for (final String raw in box.values)
            if (_decode(raw) case final OmrAnswer a)
              if (a.omrId == omrId) a,
        ]..sort(
          (OmrAnswer a, OmrAnswer b) => a.questionNumber.compareTo(b.questionNumber),
        );
        return matches;
      }, onError: _mapError);

  @override
  Future<Result<OmrAnswer?>> getAnswer(String omrAnswerId) => guardAsync(() async {
    final Box<String> box = await _openBox();
    final String? raw = box.get(omrAnswerId);
    return raw == null ? null : _decode(raw, key: omrAnswerId, box: box);
  }, onError: _mapError);

  @override
  Future<Result<List<OmrAnswer>>> createAnswers(List<OmrAnswer> answers) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        await box.putAll(<String, String>{
          for (final OmrAnswer answer in answers)
            answer.omrAnswerId: jsonEncode(answer.toJson()),
        });
        return answers;
      }, onError: _mapError);

  OmrAnswer? _decode(String raw, {String? key, Box<String>? box}) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      _logger.warning('omr_answer_malformed');
      if (key != null) {
        box?.delete(key);
      }
      return null;
    }
    final OmrAnswer? answer = OmrAnswer.tryFromJson(decoded);
    if (answer == null) {
      _logger.warning('omr_answer_unreadable');
      if (key != null) {
        box?.delete(key);
      }
    }
    return answer;
  }

  Future<Box<String>> _openBox() async => _hive.isBoxOpen(LocalBoxes.omrAnswers)
      ? _hive.box<String>(LocalBoxes.omrAnswers)
      : _hive.openBox<String>(LocalBoxes.omrAnswers);

  Failure _mapError(Object error, StackTrace stackTrace) =>
      StorageFailure.localWrite(diagnostic: 'omr answers: $error', cause: error);
}
