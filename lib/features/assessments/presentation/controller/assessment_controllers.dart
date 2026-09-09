/// Providers for the assessment screens.
///
/// The list reuses `PagedListController`; single-entity reads are
/// `FutureProvider.family`, matching `hierarchy_providers.dart`. Family types
/// are inferred because Riverpod 3 does not export them from
/// `package:flutter_riverpod`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/repository/assessment_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

final class AssessmentListController extends PagedListController<Assessment> {
  AssessmentStatus? _status;

  AssessmentStatus? get statusFilter => _status;

  void setStatusFilter(AssessmentStatus? status) {
    if (status == _status) {
      return;
    }
    _status = status;
    refresh();
  }

  @override
  Future<Result<Page<Assessment>>> fetchPage({
    required String query,
    required Object? cursor,
  }) {
    final AssessmentRepository repository = ref.read(
      assessmentRepositoryProvider,
    );
    return repository.listAssessments(
      scope: _scope(),
      query: query,
      status: _status,
      cursor: cursor,
    );
  }

  /// Falls back to an empty school-level scope, which reaches nothing —
  /// a missing session must never read as "global".
  AccessScope _scope() {
    final SessionState session = ref.read(sessionProvider);
    return session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
  }
}

final
AsyncNotifierProvider<AssessmentListController, PagedListState<Assessment>>
assessmentListControllerProvider =
    AsyncNotifierProvider<
      AssessmentListController,
      PagedListState<Assessment>
    >(AssessmentListController.new);

/// One assessment.
final assessmentProvider =
    FutureProvider.family<Assessment, String>((Ref ref, String id) async {
      final Result<Assessment> result = await ref
          .watch(assessmentRepositoryProvider)
          .getAssessment(id);
      return switch (result) {
        Success<Assessment>(:final Assessment value) => value,
        FailureResult<Assessment>(:final failure) => throw failure,
      };
    });

/// Every answer key version for an assessment, newest first.
///
/// The whole history rather than just the current key: a correction is only
/// meaningful next to what it replaced, and hiding superseded versions would
/// make "why did this child's mark change?" unanswerable from the UI.
final answerKeyVersionsProvider =
    FutureProvider.family<List<AnswerKey>, String>((Ref ref, String id) async {
      final Result<List<AnswerKey>> result = await ref
          .watch(assessmentRepositoryProvider)
          .listAnswerKeyVersions(id);
      return switch (result) {
        Success<List<AnswerKey>>(:final List<AnswerKey> value) => value,
        FailureResult<List<AnswerKey>>(:final failure) => throw failure,
      };
    });

/// A school's name, for showing an assignment as a place rather than an id.
///
/// Falls back to the id when the school cannot be read: a Supervisor looking
/// at an assessment assigned outside their scope should see that it *is*
/// assigned somewhere, without that somewhere being named.
final schoolNameProvider =
    FutureProvider.family<String, String>((Ref ref, String schoolId) async {
      final result = await ref
          .watch(schoolHierarchyRepositoryProvider)
          .getSchool(schoolId);
      return result.valueOrNull?.schoolName ?? schoolId;
    });

/// The schools sitting an assessment.
final assessmentAssignmentsProvider =
    FutureProvider.family<List<AssessmentAssignment>, String>((
      Ref ref,
      String id,
    ) async {
      final Result<List<AssessmentAssignment>> result = await ref
          .watch(assessmentRepositoryProvider)
          .listAssignments(id);
      return switch (result) {
        Success<List<AssessmentAssignment>>(
          :final List<AssessmentAssignment> value,
        ) =>
          value,
        FailureResult<List<AssessmentAssignment>>(:final failure) =>
          throw failure,
      };
    });
