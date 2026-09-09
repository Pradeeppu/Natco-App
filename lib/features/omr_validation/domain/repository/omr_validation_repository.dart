/// The validation workflow: which sheets need a human decision, and
/// recording that decision (docs/02-data-model.md §6, requirement §20).
///
/// Manual student identification for an unreadable id bubble grid is a
/// capture-flow concern (phase 5) and is deliberately not here — this
/// repository's whole charter is answers a machine could not read with
/// confidence, once the sheet and the student on it are already known.
///
/// [listSubmissionsForAssessment] is a deliberate, narrow exception to that
/// charter: phase 6 has no dedicated processing repository yet, and scoring
/// (phase 8) needs to find every submission for an assessment, not only the
/// ones with something flagged. It reads the same `omr_submissions` storage
/// this repository already owns. When phase 6 lands a proper
/// `OmrSubmissionRepository`, this method moves there and this repository
/// goes back to being validation-only.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';

abstract interface class OmrValidationRepository {
  /// Submissions with at least one answer waiting on a person, scope-filtered
  /// exactly like every other list — see `SchoolHierarchyRepository`'s doc for
  /// why the filter has to be applied in the query rather than after paging.
  Future<Result<Page<OmrSubmission>>> listQueue({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<OmrSubmission>> getSubmission(String omrId);

  /// Every submission for [assessmentId], scope-filtered — see the file doc
  /// for why this narrow exception lives here rather than in a phase-6
  /// processing repository that does not exist yet.
  Future<Result<Page<OmrSubmission>>> listSubmissionsForAssessment({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  /// Every answer on the sheet, ordered by question number — the machine's
  /// evidence for the whole submission, not only the flagged questions, so a
  /// validator can see the sheet as a whole rather than one bubble at a time
  /// with no context.
  Future<Result<List<OmrAnswer>>> getAnswers(String omrId);

  Future<Result<List<OmrValidationRecord>>> getValidationHistory(String omrId);

  /// Records a validator's decision for one question.
  ///
  /// [chosenAnswer] is one of `kAnswerOptions`, or the literal strings
  /// `'Blank'`/`'Multiple'` — the two decisions that are not an option letter.
  /// Updates [OmrAnswer.finalAnswer] and appends an [OmrValidationRecord];
  /// every machine-evidence field on the answer is carried forward untouched
  /// by construction (`OmrAnswer.withValidation`), and when every flagged
  /// answer on the submission has a decision, [OmrSubmission.validationStatus]
  /// moves to [ValidationStatus.completed].
  Future<Result<OmrAnswer>> recordDecision({
    required String omrId,
    required int questionNumber,
    required String chosenAnswer,
    String? reason,
    required String actorUserId,
    required String actorRole,
  });

  /// Persists `ScoringEngine`'s per-question output. The only caller is
  /// `ResultRepositoryImpl`, and the only fields that change on each answer
  /// are `isCorrect`/`marks` — every machine and validation field arrives
  /// already carried forward, because `OmrAnswer.withScore` has no parameter
  /// that could touch them (Critical Rule 5).
  Future<Result<void>> applyScoredAnswers(List<OmrAnswer> scoredAnswers);

  /// Marks [omrId] scored and records the machine/final score and the key
  /// version it was scored against. Another narrow exception noted in the
  /// file doc: moving `processingStatus` to `SCORED` is this submission's own
  /// state, but nothing else in this pass owns writing it.
  Future<Result<OmrSubmission>> markScored(
    String omrId, {
    required int answerKeyVersion,
    required double machineScore,
    required double finalScore,
  });
}
