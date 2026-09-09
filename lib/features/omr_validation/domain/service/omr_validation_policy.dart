/// The rules governing a human validation decision (Critical Rule 3,
/// requirement §20).
///
/// Decided here, once, rather than in a repository or a screen, for the same
/// reason `AnswerKeyPolicy` exists: these checks must not depend on whichever
/// caller happens to remember them, and must be provable with no backend.
///
/// Three things hold:
///
/// 1. A decision must be a real answer to the sheet — one of the printed
///    options, or an explicit `Blank`/`Multiple`. Free text here would let a
///    typo become an unscoreable answer with no error until scoring runs.
/// 2. The machine's reading is never the thing that changes. Applying a
///    decision only ever produces `OmrAnswer.withValidation`, which has no
///    parameter that could touch a machine-evidence field.
/// 3. A submission cannot be scored while any of its answers still needs a
///    person — checked on [OmrSubmission] itself via `readyForScoring`, and
///    restated here as [checkCanScore] so the scoring feature has one call to
///    make rather than needing to know the submission's internal shape.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';

/// The two decisions a validator may record that are not an option letter.
const String kBlankDecision = 'Blank';
const String kMultipleDecision = 'Multiple';

abstract final class OmrValidationPolicy {
  /// Every value a validator may choose for one question.
  static List<String> choicesFor() => <String>[
    ...kAnswerOptions,
    kBlankDecision,
    kMultipleDecision,
  ];

  /// Whether [chosenAnswer] is something scoring can act on.
  static Failure? checkChoice(String chosenAnswer) {
    if (choicesFor().contains(chosenAnswer)) {
      return null;
    }
    return ValidationFailure(
      userMessage:
          'Choose one of ${kAnswerOptions.join(', ')}, or mark the question '
          'Blank or Multiple.',
      diagnostic: 'invalid validation choice "$chosenAnswer"',
    );
  }

  /// Whether [answer] may still be validated.
  ///
  /// An answer the machine already trusted (`needsValidation == false`) is
  /// not blocked from a decision — a Supervisor spot-checking a high-
  /// confidence read is a legitimate use of `reviewExceptions` — but a second
  /// decision on an already-validated answer replaces the *final* answer
  /// while the [OmrValidationRecord] log keeps both, so nothing is lost
  /// either way.
  static Failure? checkAnswerBelongsToSubmission({
    required OmrAnswer answer,
    required String omrId,
  }) {
    if (answer.omrId != omrId) {
      return ValidationFailure(
        userMessage: 'This answer does not belong to this sheet.',
        diagnostic: 'answer.omrId=${answer.omrId} != omrId=$omrId',
      );
    }
    return null;
  }

  /// Whether [submission] may move to `SCORED`.
  ///
  /// Restates `OmrSubmission.readyForScoring` as a [Failure] with a message a
  /// screen can show directly, so the scoring feature never has to decode the
  /// entity's own boolean into English itself.
  static Failure? checkCanScore(OmrSubmission submission) {
    if (submission.readyForScoring) {
      return null;
    }
    if (submission.needsValidation) {
      return ValidationFailure(
        userMessage:
            'This sheet cannot be scored yet. Some answers are still '
            'waiting on a validation decision.',
        diagnostic:
            'scoring attempted on ${submission.omrId} with '
            '${submission.validationStatus.wireName}',
      );
    }
    return ValidationFailure(
      userMessage:
          'This sheet has not finished processing yet and cannot be scored.',
      diagnostic:
          'scoring attempted on ${submission.omrId} with '
          '${submission.processingStatus.wireName}',
    );
  }

  /// Whether every flagged answer on a submission now has a final decision,
  /// given the freshly-updated set of [answers] for it.
  ///
  /// Called after every [OmrAnswer.withValidation] write, so
  /// `OmrSubmission.validationStatus` can move to `COMPLETED` the moment the
  /// last flagged question is resolved rather than waiting for a separate
  /// pass to notice.
  static bool isFullyValidated(List<OmrAnswer> answers) => answers.every(
    (OmrAnswer a) => !a.needsValidation || a.finalAnswer != null,
  );
}
