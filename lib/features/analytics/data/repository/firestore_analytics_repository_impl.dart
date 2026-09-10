/// Reads the pre-aggregated rollups a Cloud Function maintains on result
/// publication (docs/02-data-model.md §7) — `question_analytics` and
/// `scope_analytics`, both `allow write: if false` to every client
/// (`firebase/firestore.rules`). The only file in `features/analytics/data`
/// that imports `cloud_firestore`; compiled and unit-testable, but not yet
/// exercised against a live project, the same status every other Firestore
/// repository in this app ships in — there is no Cloud Function deployed to
/// populate these collections yet either.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/analytics/domain/entity/question_analytics.dart';
import 'package:natco_app/features/analytics/domain/repository/analytics_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class FirestoreAnalyticsRepositoryImpl implements AnalyticsRepository {
  FirestoreAnalyticsRepositoryImpl(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<AssessmentAnalyticsSummary>> getSummary({
    required String assessmentId,
    required AccessScope scope,
  }) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.scopeAnalytics)
              .doc('${assessmentId}_${scope.level.wireName}_'
                  '${scope.definingIds.isEmpty ? "global" : scope.definingIds.first}')
              .get(),
          onError: _mapFirestoreError,
        );
    if (snapshot.isFailure) {
      return err(snapshot.failureOrNull!);
    }
    final Map<String, dynamic>? data = snapshot.valueOrNull!.data();
    if (data == null) {
      // No rollup yet — an assessment nobody has scored, not an error.
      return ok(
        const AssessmentAnalyticsSummary(
          scoredCount: 0,
          expectedCount: 0,
          averagePercentage: 0,
          highestPercentage: 0,
          lowestPercentage: 0,
          capturedCount: 0,
          needsValidationCount: 0,
        ),
      );
    }
    double asDouble(Object? v) => switch (v) {
      final num value => value.toDouble(),
      _ => 0,
    };
    int asInt(Object? v) => switch (v) {
      final num value => value.toInt(),
      _ => 0,
    };
    return ok(
      AssessmentAnalyticsSummary(
        scoredCount: asInt(data['scoredCount']),
        expectedCount: asInt(data['expectedCount']),
        averagePercentage: asDouble(data['averagePercentage']),
        highestPercentage: asDouble(data['highestPercentage']),
        lowestPercentage: asDouble(data['lowestPercentage']),
        capturedCount: asInt(data['capturedCount']),
        needsValidationCount: asInt(data['needsValidationCount']),
      ),
    );
  }

  @override
  Future<Result<List<QuestionAnalytics>>> getQuestionAnalytics({
    required String assessmentId,
    required AccessScope scope,
  }) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      () => _firestore
          .collection(Collections.questionAnalytics)
          .where('assessmentId', isEqualTo: assessmentId)
          .where('scopeLevel', isEqualTo: scope.level.wireName)
          .orderBy('questionNumber')
          .get(),
      onError: _mapFirestoreError,
    );
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final Failure failure) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok(
        value.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  _tryDecode(doc.data()),
            )
            .whereType<QuestionAnalytics>()
            .toList(growable: false),
      ),
    };
  }

  QuestionAnalytics? _tryDecode(Map<String, dynamic> data) {
    final Object? questionNumber = data['questionNumber'];
    if (questionNumber is! num) {
      return null;
    }
    int asInt(Object? v) => switch (v) {
      final num value => value.toInt(),
      _ => 0,
    };
    return QuestionAnalytics(
      questionNumber: questionNumber.toInt(),
      totalResponses: asInt(data['totalResponses']),
      correctCount: asInt(data['correctCount']),
      incorrectCount: asInt(data['incorrectCount']),
      blankCount: asInt(data['blankCount']),
      multipleMarkCount: asInt(data['multipleMarkCount']),
    );
  }

  Failure _mapFirestoreError(Object error, StackTrace stackTrace) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => PermissionFailure.denied(
          diagnostic: 'firestore permission-denied',
        ),
        'unavailable' || 'network-request-failed' => NetworkFailure.unreachable(
          diagnostic: error.code,
          cause: error,
        ),
        'deadline-exceeded' => NetworkFailure.timeout(diagnostic: error.code),
        _ => UnexpectedFailure(
          diagnostic: 'FirebaseException ${error.code}',
          cause: error,
          stackTrace: stackTrace,
        ),
      };
    }
    return UnexpectedFailure(
      diagnostic: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
