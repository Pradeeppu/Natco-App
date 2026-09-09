/// The rules governing answer keys (Critical Rule 7, requirement §14).
///
/// Three things must hold, and all three are decided here rather than in a
/// repository or a screen, so they can be unit-tested with no backend and
/// cannot be forgotten by whichever caller happens to be next:
///
/// 1. A published key is immutable. Editing one would strand every result
///    already scored against it — the marks would say one thing and the key
///    another, with nothing recording that they ever disagreed.
/// 2. A correction is a new version that names what it supersedes and why.
/// 3. A key cannot be published while it is incomplete, because scoring a
///    sheet against a missing entry silently produces a lower mark.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';

abstract final class AnswerKeyPolicy {
  /// Whether [key] may be edited in place.
  ///
  /// Only an unpublished draft. This is the single check that keeps Critical
  /// Rule 7 true on the client; `firebase/firestore.rules` keeps it true
  /// against a patched one.
  static Failure? checkEditable(AnswerKey key) {
    if (!key.isPublished) {
      return null;
    }
    return ValidationFailure(
      userMessage:
          'Answer key version ${key.version} has been published and cannot be '
          'changed. Create a correction instead — it becomes version '
          '${key.version + 1}, and the results scored against version '
          '${key.version} stay traceable.',
      diagnostic: 'edit attempted on published key v${key.version}',
    );
  }

  /// Whether [key] may be published for [assessment].
  static Failure? checkPublishable({
    required AnswerKey key,
    required Assessment assessment,
  }) {
    if (key.isPublished) {
      return ValidationFailure(
        userMessage: 'This answer key version is already published.',
        diagnostic: 'double publish of key v${key.version}',
      );
    }
    final List<int> missing = key.incompleteQuestions(
      assessment.totalQuestions,
    );
    if (missing.isNotEmpty) {
      return ValidationFailure(
        userMessage:
            'The answer key is not finished. '
            '${_questionList(missing)} still need an answer. Publishing now '
            'would score every sheet as wrong on those questions.',
        fieldErrors: <String, String>{
          for (final int q in missing) 'q$q': 'Choose an answer.',
        },
        diagnostic: 'publish attempted with ${missing.length} incomplete',
      );
    }
    if (key.isCorrection &&
        (key.changeReason == null || key.changeReason!.trim().isEmpty)) {
      return const ValidationFailure(
        userMessage:
            'Say why this correction is needed. It is shown next to every '
            'result that gets re-scored.',
        fieldErrors: <String, String>{
          'changeReason': 'Enter a reason for the correction.',
        },
        diagnostic: 'correction published with no reason',
      );
    }
    return null;
  }

  /// Builds the next version of [current], carrying its answers forward as the
  /// starting point.
  ///
  /// Copying the previous answers is deliberate: a correction is almost always
  /// a change to one or two questions, and re-entering fifty answers to fix
  /// one is how the other forty-nine get mistyped.
  static AnswerKey nextVersion(
    AnswerKey current, {
    required String answerKeyId,
    required String changeReason,
    required String createdBy,
    required DateTime createdAt,
  }) => AnswerKey(
    answerKeyId: answerKeyId,
    assessmentId: current.assessmentId,
    version: current.version + 1,
    entries: List<AnswerKeyEntry>.of(current.entries),
    isPublished: false,
    supersedesVersion: current.version,
    changeReason: changeReason,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  /// Applies one answer to a draft key.
  ///
  /// Returns a failure rather than silently ignoring a bad option or an
  /// out-of-range question: a key that quietly dropped an entry would publish
  /// as "complete" and score sheets against a hole in itself.
  static ({AnswerKey? key, Failure? failure}) setAnswer(
    AnswerKey key, {
    required int questionNumber,
    required String option,
    required int totalQuestions,
  }) {
    final Failure? notEditable = checkEditable(key);
    if (notEditable != null) {
      return (key: null, failure: notEditable);
    }
    if (questionNumber < 1 || questionNumber > totalQuestions) {
      return (
        key: null,
        failure: ValidationFailure(
          userMessage:
              'This assessment has questions 1 to $totalQuestions.',
          diagnostic: 'question $questionNumber out of range',
        ),
      );
    }
    if (!kAnswerOptions.contains(option)) {
      return (
        key: null,
        failure: ValidationFailure(
          userMessage:
              'An answer must be one of ${kAnswerOptions.join(', ')}.',
          diagnostic: 'invalid option "$option"',
        ),
      );
    }

    final List<AnswerKeyEntry> entries = List<AnswerKeyEntry>.of(key.entries);
    final int index = entries.indexWhere(
      (AnswerKeyEntry e) => e.questionNumber == questionNumber,
    );
    final AnswerKeyEntry entry = AnswerKeyEntry(
      questionNumber: questionNumber,
      correctOption: option,
      marks: index >= 0 ? entries[index].marks : null,
    );
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries
        ..add(entry)
        ..sort(
          (AnswerKeyEntry a, AnswerKeyEntry b) =>
              a.questionNumber.compareTo(b.questionNumber),
        );
    }
    return (key: key.copyWith(entries: entries), failure: null);
  }

  /// The questions whose answers differ between two versions.
  ///
  /// This is what the correction screen shows before publishing, and what the
  /// re-scoring pass in phase 8 uses to decide which results are affected —
  /// a correction to question 12 does not need every sheet re-read.
  static List<int> changedQuestions(AnswerKey from, AnswerKey to) {
    final Map<int, AnswerKeyEntry> before = from.byQuestion;
    final Map<int, AnswerKeyEntry> after = to.byQuestion;
    final Set<int> questions = <int>{...before.keys, ...after.keys};
    return <int>[
      for (final int q in questions)
        if (before[q]?.correctOption != after[q]?.correctOption) q,
    ]..sort();
  }

  static String _questionList(List<int> questions) {
    if (questions.length == 1) {
      return 'Question ${questions.single}';
    }
    if (questions.length <= 5) {
      return 'Questions ${questions.join(', ')}';
    }
    return '${questions.length} questions, starting with '
        '${questions.take(3).join(', ')}';
  }
}
