/// Tests for [ScoringEngine] — the core scoring rule (Critical Rule 5).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/results/domain/service/scoring_engine.dart';

Assessment _assessment({double negativeMark = 0}) => Assessment(
  assessmentId: 'as_1',
  assessmentName: 'Test',
  academicYear: '2026-27',
  grade: '5',
  subject: 'Numeracy',
  totalQuestions: 3,
  marksPerQuestion: 1,
  negativeMarkPerWrongAnswer: negativeMark,
  status: AssessmentStatus.active,
  omrTemplateId: 'tpl_1',
  publishedAnswerKeyVersion: 1,
  createdBy: 'admin',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

AnswerKey _key() => AnswerKey(
  answerKeyId: 'ak_1',
  assessmentId: 'as_1',
  version: 1,
  entries: const <AnswerKeyEntry>[
    AnswerKeyEntry(questionNumber: 1, correctOption: 'A'),
    AnswerKeyEntry(questionNumber: 2, correctOption: 'B'),
    AnswerKeyEntry(questionNumber: 3, correctOption: 'C'),
  ],
  isPublished: true,
  createdBy: 'admin',
  createdAt: DateTime.utc(2026),
);

OmrAnswer _answer(
  int q, {
  String? machineAnswer,
  String? finalAnswer,
  DetectionStatus status = DetectionStatus.highConfidence,
}) => OmrAnswer(
  omrAnswerId: 'ans_$q',
  omrId: 'omr_1',
  questionNumber: q,
  optionScores: const <String, double>{},
  machineAnswer: machineAnswer,
  machineConfidence: 0.9,
  machineStatus: status,
  finalAnswer: finalAnswer ?? machineAnswer,
  finalAnswerSource: AnswerSource.machine,
);

void main() {
  group('ScoringEngine.score', () {
    test('refuses to run while any answer still needs validation', () {
      final result = ScoringEngine.score(
        answers: <OmrAnswer>[
          _answer(1, machineAnswer: 'A'),
          _answer(
            2,
            machineAnswer: null,
            finalAnswer: null,
            status: DetectionStatus.lowConfidence,
          ),
          _answer(3, machineAnswer: 'C'),
        ],
        answerKey: _key(),
        assessment: _assessment(),
      );
      expect(result.outcome, isNull);
      expect(result.failure, isNotNull);
    });

    test('refuses to run when the key is missing a question', () {
      final AnswerKey incompleteKey = AnswerKey(
        answerKeyId: 'ak_2',
        assessmentId: 'as_1',
        version: 1,
        entries: const <AnswerKeyEntry>[
          AnswerKeyEntry(questionNumber: 1, correctOption: 'A'),
        ],
        isPublished: true,
        createdBy: 'admin',
        createdAt: DateTime.utc(2026),
      );
      final result = ScoringEngine.score(
        answers: <OmrAnswer>[_answer(1, machineAnswer: 'A'), _answer(2, machineAnswer: 'B')],
        answerKey: incompleteKey,
        assessment: _assessment(),
      );
      expect(result.outcome, isNull);
      expect(result.failure, isNotNull);
    });

    test('scores correct, incorrect and blank with no negative marking', () {
      final result = ScoringEngine.score(
        answers: <OmrAnswer>[
          _answer(1, machineAnswer: 'A'), // correct
          _answer(2, machineAnswer: 'A'), // wrong (key says B)
          _answer(3, machineAnswer: null), // blank
        ],
        answerKey: _key(),
        assessment: _assessment(),
      );
      final ScoringOutcome outcome = result.outcome!;
      expect(outcome.totalMarks, 3);
      expect(outcome.marksObtained, 1);
      expect(outcome.correctCount, 1);
      expect(outcome.incorrectCount, 1);
      expect(outcome.blankCount, 1);
      expect(outcome.multipleMarkCount, 0);
    });

    test('applies negative marking to wrong answers only', () {
      final result = ScoringEngine.score(
        answers: <OmrAnswer>[
          _answer(1, machineAnswer: 'A'), // correct: +1
          _answer(2, machineAnswer: 'A'), // wrong: -0.25
          _answer(3, machineAnswer: null), // blank: 0
        ],
        answerKey: _key(),
        assessment: _assessment(negativeMark: 0.25),
      );
      final ScoringOutcome outcome = result.outcome!;
      expect(outcome.marksObtained, closeTo(0.75, 0.0001));
    });

    test('a validator-recorded "Multiple" scores zero and is never wrong', () {
      final result = ScoringEngine.score(
        answers: <OmrAnswer>[
          _answer(1, machineAnswer: 'A'),
          _answer(2, machineAnswer: 'B'),
          _answer(
            3,
            machineAnswer: null,
            finalAnswer: 'Multiple',
            status: DetectionStatus.multipleMark,
          ),
        ],
        answerKey: _key(),
        assessment: _assessment(negativeMark: 1),
      );
      final ScoringOutcome outcome = result.outcome!;
      expect(outcome.multipleMarkCount, 1);
      expect(outcome.incorrectCount, 0);
      expect(outcome.marksObtained, 2); // two correct, no penalty on Q3
    });

    test('flags a discrepancy exactly where a validator overruled the machine', () {
      final result = ScoringEngine.score(
        answers: <OmrAnswer>[
          _answer(1, machineAnswer: 'A'), // untouched
          _answer(2, machineAnswer: null, finalAnswer: 'B'), // validated
          _answer(3, machineAnswer: 'C'), // untouched
        ],
        answerKey: _key(),
        assessment: _assessment(),
      );
      final ScoringOutcome outcome = result.outcome!;
      expect(outcome.discrepantQuestions, <int>[2]);
      expect(outcome.hasDiscrepancy, isTrue);
      // The machine's own (pre-validation) reading treats Q2 as blank.
      expect(outcome.machineMarksObtained, 2);
      // The final score credits Q2 once the validator's answer is counted.
      expect(outcome.marksObtained, 3);
    });

    test('scoredAnswers carries isCorrect/marks with every other field '
        'unchanged', () {
      final OmrAnswer original = _answer(1, machineAnswer: 'A');
      final result = ScoringEngine.score(
        answers: <OmrAnswer>[original],
        answerKey: _key(),
        assessment: _assessment(),
      );
      final OmrAnswer scored = result.outcome!.scoredAnswers.single;
      expect(scored.omrAnswerId, original.omrAnswerId);
      expect(scored.machineAnswer, original.machineAnswer);
      expect(scored.finalAnswer, original.finalAnswer);
      expect(scored.isCorrect, isTrue);
      expect(scored.marks, 1);
    });
  });
}
