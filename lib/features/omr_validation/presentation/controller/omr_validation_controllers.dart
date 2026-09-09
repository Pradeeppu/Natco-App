/// Providers for the validation queue and one sheet's detail.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';

final class OmrValidationQueueController
    extends PagedListController<OmrSubmission> {
  @override
  Future<Result<Page<OmrSubmission>>> fetchPage({
    required String query,
    required Object? cursor,
  }) {
    final OmrValidationRepository repository = ref.read(
      omrValidationRepositoryProvider,
    );
    return repository.listQueue(scope: _scope(), query: query, cursor: cursor);
  }

  /// Falls back to an empty school-level scope, which reaches nothing — see
  /// `StudentListController._scope` for why a missing session must never
  /// read as "global".
  AccessScope _scope() {
    final SessionState session = ref.read(sessionProvider);
    return session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
  }
}

final AsyncNotifierProvider<OmrValidationQueueController, PagedListState<OmrSubmission>>
omrValidationQueueControllerProvider =
    AsyncNotifierProvider<
      OmrValidationQueueController,
      PagedListState<OmrSubmission>
    >(OmrValidationQueueController.new);

/// One submission, for the detail screen's header.
///
/// Type inferred, not written out — Riverpod 3 does not export family
/// provider types from `package:flutter_riverpod`, the same reason
/// `hierarchy_providers.dart` and `user_list_controller.dart` give.
final omrSubmissionProvider =
    FutureProvider.family<OmrSubmission, String>((Ref ref, String omrId) async {
      final Result<OmrSubmission> result = await ref
          .watch(omrValidationRepositoryProvider)
          .getSubmission(omrId);
      return switch (result) {
        Success<OmrSubmission>(:final OmrSubmission value) => value,
        FailureResult<OmrSubmission>(:final failure) => throw failure,
      };
    });

/// Every answer on the sheet, ordered by question number — refreshed after
/// each recorded decision by invalidating this provider, so the next
/// flagged question and the completeness check both see the fresh write.
final omrAnswersProvider =
    FutureProvider.family<List<OmrAnswer>, String>((Ref ref, String omrId) async {
      final Result<List<OmrAnswer>> result = await ref
          .watch(omrValidationRepositoryProvider)
          .getAnswers(omrId);
      return switch (result) {
        Success<List<OmrAnswer>>(:final List<OmrAnswer> value) => value,
        FailureResult<List<OmrAnswer>>(:final failure) => throw failure,
      };
    });
