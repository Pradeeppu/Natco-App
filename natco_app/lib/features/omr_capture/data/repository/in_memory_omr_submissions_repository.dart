/// In-memory [OmrSubmissionsRepository]. Used by demo mode and the test
/// suite, the same posture as every other in-memory repository in this app.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/quality_override.dart';
import 'package:natco_app/features/omr_capture/domain/repository/omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/domain/service/omr_state_machine.dart';

final class InMemoryOmrSubmissionsRepository implements OmrSubmissionsRepository {
  InMemoryOmrSubmissionsRepository({required Clock clock}) : _clock = clock;

  final Clock _clock;
  static const OmrStateMachine _stateMachine = OmrStateMachine();

  final Map<String, OmrSubmission> _submissions = <String, OmrSubmission>{};

  @override
  Future<Result<List<OmrSubmission>>> listForSession(String sessionId) async {
    final List<OmrSubmission> matches = _submissions.values
        .where((OmrSubmission s) => s.sessionId == sessionId)
        .toList()
      ..sort((OmrSubmission a, OmrSubmission b) => a.capturedAt.compareTo(b.capturedAt));
    return ok(matches);
  }

  @override
  Future<Result<OmrSubmission?>> getSubmission(String submissionId) async =>
      ok(_submissions[submissionId]);

  @override
  Future<Result<OmrSubmission>> createSubmission(
    OmrSubmission submission,
  ) async {
    _submissions[submission.submissionId] = submission;
    return ok(submission);
  }

  @override
  Future<Result<OmrSubmission>> overrideQualityGate(
    String submissionId,
    QualityOverride override,
  ) async {
    final OmrSubmission? existing = _submissions[submissionId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That submission could not be found.',
          entityType: 'omr_submission',
          entityId: submissionId,
        ),
      );
    }
    final Result<OmrProcessingStatus> transition = _stateMachine.transition(
      existing.processingStatus,
      OmrProcessingStatus.qualityChecked,
    );
    if (transition.isFailure) {
      return err(transition.failureOrNull!);
    }
    final OmrSubmission updated = existing.copyWith(
      processingStatus: transition.valueOrNull!,
      qualityOverride: override,
      updatedAt: _clock.nowUtc(),
    );
    _submissions[submissionId] = updated;
    return ok(updated);
  }

  @override
  Future<Result<List<OmrSubmission>>> listInScope(AccessScope scope) async {
    final List<OmrSubmission> matches = _submissions.values.where((
      OmrSubmission s,
    ) {
      return scope.covers(
        ScopeTarget(
          stateId: s.stateId,
          districtId: s.districtId,
          clusterId: s.clusterId,
          schoolId: s.schoolId,
        ),
      );
    }).toList()..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return ok(matches);
  }
}
