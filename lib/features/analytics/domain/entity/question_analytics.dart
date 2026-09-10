/// A rollup of how one question performed across a scope
/// (docs/02-data-model.md §7).
///
/// In a real deployment this is written once, server-side, by a Cloud
/// Function on result publication — "so that a district dashboard never fans
/// out over a hundred thousand answer documents from a phone," in this
/// project's own words. `AnalyticsRepositoryImpl`'s demo path computes it
/// live from the same real `AssessmentResult`/`OmrAnswer` records the results
/// screen shows, which is what makes "metrics reconcile against raw results"
/// true by construction rather than by trusting a cache to stay in sync —
/// acceptable at the demo dataset's scale, and exactly why the doc calls for
/// a server rollup at real scale instead.
library;

final class QuestionAnalytics {
  const QuestionAnalytics({
    required this.questionNumber,
    required this.totalResponses,
    required this.correctCount,
    required this.incorrectCount,
    required this.blankCount,
    required this.multipleMarkCount,
  });

  final int questionNumber;
  final int totalResponses;
  final int correctCount;
  final int incorrectCount;
  final int blankCount;
  final int multipleMarkCount;

  double get correctPercentage =>
      totalResponses == 0 ? 0 : (correctCount / totalResponses) * 100;

  double get blankPercentage =>
      totalResponses == 0 ? 0 : (blankCount / totalResponses) * 100;

  @override
  bool operator ==(Object other) =>
      other is QuestionAnalytics &&
      other.questionNumber == questionNumber &&
      other.totalResponses == totalResponses &&
      other.correctCount == correctCount &&
      other.incorrectCount == incorrectCount &&
      other.blankCount == blankCount &&
      other.multipleMarkCount == multipleMarkCount;

  @override
  int get hashCode => Object.hash(
    questionNumber,
    totalResponses,
    correctCount,
    incorrectCount,
    blankCount,
    multipleMarkCount,
  );

  @override
  String toString() =>
      'QuestionAnalytics(Q$questionNumber, '
      '${correctPercentage.toStringAsFixed(0)}% correct of $totalResponses)';
}

/// Scope-level summary for one assessment — the numbers a Supervisor's
/// landing view leads with, before the question-by-question detail.
final class AssessmentAnalyticsSummary {
  const AssessmentAnalyticsSummary({
    required this.scoredCount,
    required this.expectedCount,
    required this.averagePercentage,
    required this.highestPercentage,
    required this.lowestPercentage,
    required this.capturedCount,
    required this.needsValidationCount,
  });

  final int scoredCount;

  /// From every in-scope session's roster — how many students should
  /// eventually have a result, whether or not their sheet exists yet.
  final int expectedCount;

  final double averagePercentage;
  final double highestPercentage;
  final double lowestPercentage;

  /// Every OMR submission captured in scope, regardless of processing stage
  /// — a real count of real records, not the pipeline-stage breakdown a
  /// server rollup would carry (phases 5-6 do not exist yet to produce the
  /// finer stages honestly).
  final int capturedCount;
  final int needsValidationCount;

  double get completionPercentage =>
      expectedCount == 0 ? 0 : (scoredCount / expectedCount) * 100;

  @override
  String toString() =>
      'AssessmentAnalyticsSummary($scoredCount/$expectedCount scored, '
      'avg ${averagePercentage.toStringAsFixed(0)}%)';
}
