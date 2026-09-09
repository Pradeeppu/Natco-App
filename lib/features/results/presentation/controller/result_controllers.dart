/// Providers for the results list and one student's result.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';

final class ResultListController extends PagedListController<AssessmentResult> {
  String? _assessmentId;

  String? get assessmentId => _assessmentId;

  void setAssessment(String assessmentId) {
    if (assessmentId == _assessmentId) {
      return;
    }
    _assessmentId = assessmentId;
    refresh();
  }

  @override
  Future<Result<Page<AssessmentResult>>> fetchPage({
    required String query,
    required Object? cursor,
  }) async {
    final String? id = _assessmentId;
    if (id == null) {
      return ok((items: const <AssessmentResult>[], nextCursor: null, hasMore: false));
    }
    return ref
        .read(resultRepositoryProvider)
        .listResults(assessmentId: id, scope: _scope(), cursor: cursor);
  }

  /// Falls back to an empty school-level scope — see
  /// `StudentListController._scope` for why a missing session must never
  /// read as "global".
  AccessScope _scope() {
    final SessionState session = ref.read(sessionProvider);
    return session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
  }
}

final AsyncNotifierProvider<ResultListController, PagedListState<AssessmentResult>>
resultListControllerProvider =
    AsyncNotifierProvider<
      ResultListController,
      PagedListState<AssessmentResult>
    >(ResultListController.new);

/// One student's result for one assessment, or `null` if their sheet has not
/// been scored yet. Family key is a record rather than a composite string —
/// records are structurally `==`, so this works as a Riverpod family
/// parameter with no manual key-building.
final resultForStudentProvider =
    FutureProvider.family<
      AssessmentResult?,
      ({String assessmentId, String studentId})
    >((Ref ref, ({String assessmentId, String studentId}) key) async {
      final Result<AssessmentResult?> result = await ref
          .watch(resultRepositoryProvider)
          .getResultForStudent(
            assessmentId: key.assessmentId,
            studentId: key.studentId,
          );
      return switch (result) {
        Success<AssessmentResult?>(:final AssessmentResult? value) => value,
        FailureResult<AssessmentResult?>(:final failure) => throw failure,
      };
    });

/// Every answer on a result's sheet, for the question-by-question table.
final resultAnswersProvider =
    FutureProvider.family<List<OmrAnswer>, String>((Ref ref, String omrId) async {
      final Result<List<OmrAnswer>> result = await ref
          .watch(omrValidationRepositoryProvider)
          .getAnswers(omrId);
      return switch (result) {
        Success<List<OmrAnswer>>(:final List<OmrAnswer> value) => value,
        FailureResult<List<OmrAnswer>>(:final failure) => throw failure,
      };
    });
