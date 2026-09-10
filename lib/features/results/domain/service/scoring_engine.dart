/// The scoring rule (docs/02-data-model.md §7, Critical Rule 5).
///
/// Pure Dart, no repository, no Flutter — a score is a deterministic function
/// of three pieces of already-loaded data, and testing it should never need a
/// backend. The rule itself is simple on purpose:
///
/// * A blank or a machine/human "Multiple" decision earns no marks and is
///   never counted wrong — a child who did not answer has not made an error.
/// * A wrong option loses [Assessment.negativeMarkPerWrongAnswer] marks
///   (zero unless the programme uses negative marking).
/// * Refuses to run at all while any answer still needs a person — Critical
///   Rule 3's "no score before validation" restated as something scoring
///   itself checks, not only something the caller remembers to check first.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_validation/domain/service/omr_validation_policy.dart';

/// The result of scoring one sheet: the totals, and the per-question
/// [OmrAnswer]s with `isCorrect`/`marks` now filled in via `withScore` — the
/// only way those two fields are ever set (§ Critical Rule 5).
final class ScoringOutcome {
  const ScoringOutcome({
    required this.totalMarks,
    required this.marksObtained,
    required this.machineMarksObtained,
    required this.correctCount,
    required this.incorrectCount,
    required this.blankCount,
    required this.multipleMarkCount,
    required this.discrepantQuestions,
    required this.scoredAnswers,
  });

  final double totalMarks;

  /// The score against [OmrAnswer.finalAnswer] — what a human ultimately
  /// decided, wherever a decision was needed. This is what a result records.
  final double marksObtained;

  /// The same computation against [OmrAnswer.machineAnswer] alone, ignoring
  /// every validation decision — docs/06's on-device preview number, kept
  /// even after validation completes so it can be compared against the final
  /// score rather than discarded the moment a person looks at the sheet.
  final double machineMarksObtained;

  final int correctCount;
  final int incorrectCount;
  final int blankCount;
  final int multipleMarkCount;

  /// Question numbers where the machine's own reading and the final answer
  /// disagree — always exactly the questions a validator overruled, since a
  /// question nobody touched has `finalAnswer == machineAnswer` by
  /// construction. Surfaced rather than silently reconciled: a validator
  /// disagreeing with the machine is the system working, not an error to
  /// hide.
  final List<int> discrepantQuestions;

  final List<OmrAnswer> scoredAnswers;

  bool get hasDiscrepancy => discrepantQuestions.isNotEmpty;
}

abstract final class ScoringEngine {
  /// Scores [answers] against [answerKey], using [assessment] for
  /// per-question marks and the negative-marking rule.
  ///
  /// Returns a [Failure] rather than a partial score when any answer still
  /// needs a person (`OmrValidationPolicy.checkCanScore`'s sibling check,
  /// applied per-answer here since this runs before a submission's aggregate
  /// status is necessarily in sync) or when the key has no entry for a
  /// question the sheet carries — a missing key entry is this system's
  /// failure, not the child's, and must not silently score as wrong.
  static ({ScoringOutcome? outcome, Failure? failure}) score({
    required List<OmrAnswer> answers,
    required AnswerKey answerKey,
    required Assessment assessment,
  }) {
    final List<OmrAnswer> stillFlagged = answers
        .where((OmrAnswer a) => a.needsValidation && a.finalAnswer == null)
        .toList();
    if (stillFlagged.isNotEmpty) {
      return (
        outcome: null,
        failure: ValidationFailure(
          userMessage:
              'This sheet cannot be scored yet. ${stillFlagged.length} '
              'answer(s) still need a validation decision.',
          diagnostic:
              'scoring attempted with ${stillFlagged.length} unresolved '
              'answers',
        ),
      );
    }

    double totalMarks = 0;
    double marksObtained = 0;
    double machineMarksObtained = 0;
    int correct = 0;
    int incorrect = 0;
    int blank = 0;
    int multiple = 0;
    final List<int> discrepant = <int>[];
    final List<OmrAnswer> scored = <OmrAnswer>[];

    for (final OmrAnswer answer in answers) {
      final AnswerKeyEntry? entry = answerKey.byQuestion[answer.questionNumber];
      if (entry == null) {
        return (
          outcome: null,
          failure: ValidationFailure(
            userMessage:
                'The answer key has no entry for question '
                '${answer.questionNumber}. Fix the key before scoring.',
            diagnostic:
                'answer key v${answerKey.version} missing question '
                '${answer.questionNumber}',
          ),
        );
      }
      final double questionMarks = entry.marks ?? assessment.marksPerQuestion;
      final double penalty = assessment.negativeMarkPerWrongAnswer;
      totalMarks += questionMarks;

      final String? machineAnswer = answer.machineAnswer;
      final bool isMachineBlank =
          machineAnswer == null || machineAnswer == kBlankDecision;
      final bool isMachineMultiple = machineAnswer == kMultipleDecision;

      if (!isMachineBlank && !isMachineMultiple) {
        machineMarksObtained += _markFor(
          answer: machineAnswer,
          correctOption: entry.correctOption,
          questionMarks: questionMarks,
          penalty: penalty,
        );
      }
      if (answer.machineAnswer != answer.finalAnswer) {
        discrepant.add(answer.questionNumber);
      }

      final String? finalAnswer = answer.finalAnswer;
      final bool isBlank =
          finalAnswer == null || finalAnswer == kBlankDecision;
      final bool isMultiple = finalAnswer == kMultipleDecision;

      if (isBlank) {
        blank++;
        scored.add(answer.withScore(isCorrect: false, marks: 0));
        continue;
      }
      if (isMultiple) {
        multiple++;
        scored.add(answer.withScore(isCorrect: false, marks: 0));
        continue;
      }

      if (finalAnswer == entry.correctOption) {
        correct++;
        marksObtained += questionMarks;
        scored.add(answer.withScore(isCorrect: true, marks: questionMarks));
      } else {
        incorrect++;
        marksObtained -= penalty;
        scored.add(answer.withScore(isCorrect: false, marks: -penalty));
      }
    }

    return (
      outcome: ScoringOutcome(
        totalMarks: totalMarks,
        // A negative-marking programme can drive either total below zero on
        // a bad sheet; reporting the true value is more honest than clamping
        // it and hiding how negative marking actually behaved.
        marksObtained: marksObtained,
        machineMarksObtained: machineMarksObtained,
        correctCount: correct,
        incorrectCount: incorrect,
        blankCount: blank,
        multipleMarkCount: multiple,
        discrepantQuestions: discrepant,
        scoredAnswers: scored,
      ),
      failure: null,
    );
  }

  /// Marks for one option against [correctOption] — `null` (a genuine blank)
  /// scores zero and is never penalised, matching the rule the main loop
  /// applies to `finalAnswer`.
  static double _markFor({
    required String? answer,
    required String correctOption,
    required double questionMarks,
    required double penalty,
  }) {
    if (answer == null) {
      return 0;
    }
    return answer == correctOption ? questionMarks : -penalty;
  }
}
