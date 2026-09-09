/// One-shot lookups for the assessment detail and answer-key screens.
///
/// `FutureProvider.family` rather than a hand-written `Notifier`, the same
/// reasoning as `schoolDetailProvider`: Riverpod's code-free `Notifier` has no
/// family support in this version, and a one-shot fetch is exactly what
/// `FutureProvider` is for.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

/// Thrown into the provider's `AsyncValue.error` so the screen can render a
/// [Failure] the same way every other screen does, via `FailureView`.
final class AssessmentDetailFailure implements Exception {
  const AssessmentDetailFailure(this.failure);

  final Failure failure;
}

final assessmentDetailProvider = FutureProvider.family<Assessment?, String>((
  Ref ref,
  String assessmentId,
) async {
  final Result<Assessment?> result = await ref
      .watch(assessmentsRepositoryProvider)
      .getAssessment(assessmentId);
  return switch (result) {
    Success<Assessment?>(:final value) => value,
    FailureResult<Assessment?>(:final failure) => throw AssessmentDetailFailure(
      failure,
    ),
  };
});

final assessmentQuestionsProvider =
    FutureProvider.family<List<AssessmentQuestion>, String>((
      Ref ref,
      String assessmentId,
    ) async {
      final Result<List<AssessmentQuestion>> result = await ref
          .watch(assessmentsRepositoryProvider)
          .listQuestions(assessmentId);
      return switch (result) {
        Success<List<AssessmentQuestion>>(:final value) => value,
        FailureResult<List<AssessmentQuestion>>(:final failure) =>
          throw AssessmentDetailFailure(failure),
      };
    });

final answerKeyVersionsProvider =
    FutureProvider.family<List<AnswerKey>, String>((
      Ref ref,
      String assessmentId,
    ) async {
      final Result<List<AnswerKey>> result = await ref
          .watch(assessmentsRepositoryProvider)
          .listAnswerKeyVersions(assessmentId);
      return switch (result) {
        Success<List<AnswerKey>>(:final value) => value,
        FailureResult<List<AnswerKey>>(:final failure) =>
          throw AssessmentDetailFailure(failure),
      };
    });

/// Assignments for one assessment, restricted to the caller's scope.
final assessmentAssignmentsProvider =
    FutureProvider.family<List<AssessmentAssignment>, String>((
      Ref ref,
      String assessmentId,
    ) async {
      final AccessScope scope =
          ref.watch(sessionProvider).authorization.user?.scope ??
          const AccessScope(level: ScopeLevel.school);
      final Result<Page<AssessmentAssignment>> result = await ref
          .watch(assessmentsRepositoryProvider)
          .listAssignments(scope: scope, assessmentId: assessmentId);
      return switch (result) {
        Success<Page<AssessmentAssignment>>(:final value) => value.items,
        FailureResult<Page<AssessmentAssignment>>(:final failure) =>
          throw AssessmentDetailFailure(failure),
      };
    });
