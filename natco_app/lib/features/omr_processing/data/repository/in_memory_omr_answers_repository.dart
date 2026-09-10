/// In-memory [OmrAnswersRepository] — demo mode and tests.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/repository/omr_answers_repository.dart';

final class InMemoryOmrAnswersRepository implements OmrAnswersRepository {
  final Map<String, OmrAnswer> _byId = <String, OmrAnswer>{};

  @override
  Future<Result<List<OmrAnswer>>> listForOmrId(String omrId) async => ok(
    _byId.values.where((OmrAnswer a) => a.omrId == omrId).toList(growable: false)
      ..sort((OmrAnswer a, OmrAnswer b) => a.questionNumber.compareTo(b.questionNumber)),
  );

  @override
  Future<Result<OmrAnswer?>> getAnswer(String omrAnswerId) async =>
      ok(_byId[omrAnswerId]);

  @override
  Future<Result<List<OmrAnswer>>> createAnswers(List<OmrAnswer> answers) async {
    for (final OmrAnswer answer in answers) {
      _byId[answer.omrAnswerId] = answer;
    }
    return ok(answers);
  }
}
