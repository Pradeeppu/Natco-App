/// Captured OMR submissions, as seen by the presentation layer.
///
/// Local-first for the same reason `AssessmentSessionsRepository` is
/// (docs/06-offline-sync-strategy.md §1): a submission has to be creatable
/// and readable with no network at all.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/quality_override.dart';

abstract interface class OmrSubmissionsRepository {
  Future<Result<List<OmrSubmission>>> listForSession(String sessionId);

  Future<Result<OmrSubmission?>> getSubmission(String submissionId);

  Future<Result<OmrSubmission>> createSubmission(OmrSubmission submission);

  /// Applies a quality-gate override to a `QUALITY_FAILED` submission,
  /// moving it back to `QUALITY_CHECKED`. Fails with
  /// `IllegalStateTransitionFailure` for a submission not currently
  /// `QUALITY_FAILED` — this method is the override action, not a general
  /// status setter (docs/04-security-model.md: `overrideQualityGate` alone
  /// may do this; the caller is responsible for that permission check).
  Future<Result<OmrSubmission>> overrideQualityGate(
    String submissionId,
    QualityOverride override,
  );

  /// Restricted to submissions [scope] covers, mirroring
  /// `AssessmentSessionsRepository.listSessions` — a Supervisor reviewing
  /// exceptions sees only their own schools' captures.
  Future<Result<List<OmrSubmission>>> listInScope(AccessScope scope);
}
