/// Per-question machine answers, as seen by the presentation layer.
///
/// Local-first for the same reason `OmrSubmissionsRepository` is: an answer
/// record is written the moment the engine finishes processing a sheet,
/// which has to succeed with no network at all.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';

abstract interface class OmrAnswersRepository {
  Future<Result<List<OmrAnswer>>> listForOmrId(String omrId);

  Future<Result<OmrAnswer?>> getAnswer(String omrAnswerId);

  /// Writes every answer the engine produced for one sheet in one call —
  /// there is no partial-write case: either the whole answer grid was
  /// classified or none of it was (`processingStatus` stays
  /// `PROCESSING_FAILED` and no answers are written at all).
  Future<Result<List<OmrAnswer>>> createAnswers(List<OmrAnswer> answers);
}
