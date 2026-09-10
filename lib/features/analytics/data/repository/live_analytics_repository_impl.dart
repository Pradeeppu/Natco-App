/// Computes analytics live from raw results and answers.
///
/// This is the demo-mode implementation, and the doc comment on
/// [QuestionAnalytics] explains why it is not how a real deployment works:
/// at real scale this fans out over every submission for the assessment on
/// every screen open, which is exactly what a Cloud Function's server-side
/// rollup exists to avoid. It is the right choice here specifically because
/// nothing in demo mode runs a Cloud Function, and because computing live is
/// what makes "metrics reconcile against raw results" true by construction
/// rather than something a second implementation could let drift.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/analytics/domain/entity/question_analytics.dart';
import 'package:natco_app/features/analytics/domain/repository/analytics_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';
import 'package:natco_app/features/results/domain/repository/result_repository.dart';

final class LiveAnalyticsRepositoryImpl implements AnalyticsRepository {
  LiveAnalyticsRepositoryImpl({
    required ResultRepository resultRepository,
    required OmrValidationRepository omrRepository,
    required SessionRepository sessionRepository,
  }) : _resultRepository = resultRepository,
       _omrRepository = omrRepository,
       _sessionRepository = sessionRepository;

  final ResultRepository _resultRepository;
  final OmrValidationRepository _omrRepository;
  final SessionRepository _sessionRepository;

  @override
  Future<Result<AssessmentAnalyticsSummary>> getSummary({
    required String assessmentId,
    required AccessScope scope,
  }) async {
    final Result<List<AssessmentResult>> resultsResult = await _allResults(
      assessmentId: assessmentId,
      scope: scope,
    );
    if (resultsResult.isFailure) {
      return err(resultsResult.failureOrNull!);
    }
    final List<AssessmentResult> results = resultsResult.valueOrNull!;

    final Result<List<OmrSubmission>> submissionsResult = await _allSubmissions(
      assessmentId: assessmentId,
      scope: scope,
    );
    if (submissionsResult.isFailure) {
      return err(submissionsResult.failureOrNull!);
    }
    final List<OmrSubmission> submissions = submissionsResult.valueOrNull!;

    final Result<List<AssessmentSession>> sessionsResult = await _sessionRepository
        .listSessions(scope: scope, assessmentId: assessmentId);
    if (sessionsResult.isFailure) {
      return err(sessionsResult.failureOrNull!);
    }
    final int expectedCount = sessionsResult.valueOrNull!.fold<int>(
      0,
      (int sum, AssessmentSession s) => sum + s.totalStudents,
    );

    final List<double> percentages = results
        .map((AssessmentResult r) => r.percentage)
        .toList(growable: false);

    return ok(
      AssessmentAnalyticsSummary(
        scoredCount: results.length,
        expectedCount: expectedCount,
        averagePercentage: percentages.isEmpty
            ? 0
            : percentages.reduce((double a, double b) => a + b) /
                  percentages.length,
        highestPercentage: percentages.isEmpty
            ? 0
            : percentages.reduce((double a, double b) => a > b ? a : b),
        lowestPercentage: percentages.isEmpty
            ? 0
            : percentages.reduce((double a, double b) => a < b ? a : b),
        capturedCount: submissions.length,
        needsValidationCount: submissions
            .where((OmrSubmission s) => s.needsValidation)
            .length,
      ),
    );
  }

  @override
  Future<Result<List<QuestionAnalytics>>> getQuestionAnalytics({
    required String assessmentId,
    required AccessScope scope,
  }) async {
    final Result<List<AssessmentResult>> resultsResult = await _allResults(
      assessmentId: assessmentId,
      scope: scope,
    );
    if (resultsResult.isFailure) {
      return err(resultsResult.failureOrNull!);
    }

    final Map<int, _Tally> byQuestion = <int, _Tally>{};
    for (final AssessmentResult result in resultsResult.valueOrNull!) {
      final Result<List<OmrAnswer>> answersResult = await _omrRepository
          .getAnswers(result.omrId);
      if (answersResult.isFailure) {
        // One sheet's answers being unreadable must not blank the whole
        // question-performance table for every other student's sheet.
        continue;
      }
      for (final OmrAnswer answer in answersResult.valueOrNull!) {
        final _Tally tally = byQuestion.putIfAbsent(
          answer.questionNumber,
          _Tally.new,
        );
        tally.total++;
        final String? finalAnswer = answer.finalAnswer;
        if (finalAnswer == null || finalAnswer == 'Blank') {
          tally.blank++;
        } else if (finalAnswer == 'Multiple') {
          tally.multiple++;
        } else if (answer.isCorrect == true) {
          tally.correct++;
        } else {
          tally.incorrect++;
        }
      }
    }

    final List<QuestionAnalytics> analytics =
        byQuestion.entries
            .map(
              (MapEntry<int, _Tally> e) => QuestionAnalytics(
                questionNumber: e.key,
                totalResponses: e.value.total,
                correctCount: e.value.correct,
                incorrectCount: e.value.incorrect,
                blankCount: e.value.blank,
                multipleMarkCount: e.value.multiple,
              ),
            )
            .toList()
          ..sort(
            (QuestionAnalytics a, QuestionAnalytics b) =>
                a.questionNumber.compareTo(b.questionNumber),
          );
    return ok(analytics);
  }

  Future<Result<List<AssessmentResult>>> _allResults({
    required String assessmentId,
    required AccessScope scope,
  }) async {
    final List<AssessmentResult> all = <AssessmentResult>[];
    Object? cursor;
    while (true) {
      final Result<Page<AssessmentResult>> pageResult = await _resultRepository
          .listResults(assessmentId: assessmentId, scope: scope, cursor: cursor);
      if (pageResult.isFailure) {
        return err(pageResult.failureOrNull!);
      }
      final Page<AssessmentResult> page = pageResult.valueOrNull!;
      all.addAll(page.items);
      if (!page.hasMore) {
        break;
      }
      cursor = page.nextCursor;
    }
    return ok(all);
  }

  Future<Result<List<OmrSubmission>>> _allSubmissions({
    required String assessmentId,
    required AccessScope scope,
  }) async {
    final List<OmrSubmission> all = <OmrSubmission>[];
    Object? cursor;
    while (true) {
      final Result<Page<OmrSubmission>> pageResult = await _omrRepository
          .listSubmissionsForAssessment(
            assessmentId: assessmentId,
            scope: scope,
            cursor: cursor,
          );
      if (pageResult.isFailure) {
        return err(pageResult.failureOrNull!);
      }
      final Page<OmrSubmission> page = pageResult.valueOrNull!;
      all.addAll(page.items);
      if (!page.hasMore) {
        break;
      }
      cursor = page.nextCursor;
    }
    return ok(all);
  }
}

final class _Tally {
  int total = 0;
  int correct = 0;
  int incorrect = 0;
  int blank = 0;
  int multiple = 0;
}
