/// Hive-backed [OmrSubmissionsRepository].
///
/// Local-first for the same reason `HiveAssessmentSessionsRepository` is: a
/// submission must be creatable with no network, and every write here is a
/// single `Box.put` of the whole record — always fully the old state or
/// fully the new one on disk, with no multi-step commit for a crash to land
/// inside (docs/06-offline-sync-strategy.md §1).
library;

import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/quality_override.dart';
import 'package:natco_app/features/omr_capture/domain/repository/omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/domain/service/omr_state_machine.dart';

final class HiveOmrSubmissionsRepository implements OmrSubmissionsRepository {
  HiveOmrSubmissionsRepository({
    required HiveInterface hive,
    required Clock clock,
    required AppLogger logger,
  }) : _hive = hive,
       _clock = clock,
       _logger = logger;

  final HiveInterface _hive;
  final Clock _clock;
  final AppLogger _logger;
  static const OmrStateMachine _stateMachine = OmrStateMachine();

  @override
  Future<Result<List<OmrSubmission>>> listForSession(String sessionId) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        final List<OmrSubmission> matches = <OmrSubmission>[
          for (final String raw in box.values)
            if (_decode(raw) case final OmrSubmission s)
              if (s.sessionId == sessionId) s,
        ]..sort(
          (OmrSubmission a, OmrSubmission b) =>
              a.capturedAt.compareTo(b.capturedAt),
        );
        return matches;
      }, onError: _mapError);

  @override
  Future<Result<OmrSubmission?>> getSubmission(String submissionId) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        final String? raw = box.get(submissionId);
        return raw == null ? null : _decode(raw, key: submissionId, box: box);
      }, onError: _mapError);

  @override
  Future<Result<OmrSubmission>> createSubmission(OmrSubmission submission) =>
      _write(submission);

  @override
  Future<Result<OmrSubmission>> overrideQualityGate(
    String submissionId,
    QualityOverride override,
  ) async {
    final Result<OmrSubmission?> current = await getSubmission(submissionId);
    if (current.isFailure) {
      return err(current.failureOrNull!);
    }
    final OmrSubmission? existing = current.valueOrNull;
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
    return _write(updated);
  }

  @override
  Future<Result<List<OmrSubmission>>> listInScope(AccessScope scope) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        final List<OmrSubmission> matches = <OmrSubmission>[
          for (final String raw in box.values)
            if (_decode(raw) case final OmrSubmission s)
              if (scope.covers(
                ScopeTarget(
                  stateId: s.stateId,
                  districtId: s.districtId,
                  clusterId: s.clusterId,
                  schoolId: s.schoolId,
                ),
              ))
                s,
        ]..sort(
          (OmrSubmission a, OmrSubmission b) =>
              b.capturedAt.compareTo(a.capturedAt),
        );
        return matches;
      }, onError: _mapError);

  Future<Result<OmrSubmission>> _write(OmrSubmission submission) =>
      guardAsync(() async {
        final Box<String> box = await _openBox();
        await box.put(submission.submissionId, jsonEncode(submission.toJson()));
        return submission;
      }, onError: _mapError);

  OmrSubmission? _decode(String raw, {String? key, Box<String>? box}) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      _logger.warning('omr_submission_malformed');
      if (key != null) {
        box?.delete(key);
      }
      return null;
    }
    final OmrSubmission? submission = OmrSubmission.tryFromJson(decoded);
    if (submission == null) {
      _logger.warning('omr_submission_unreadable');
      if (key != null) {
        box?.delete(key);
      }
    }
    return submission;
  }

  Future<Box<String>> _openBox() async => _hive.isBoxOpen(LocalBoxes.omrSubmissions)
      ? _hive.box<String>(LocalBoxes.omrSubmissions)
      : _hive.openBox<String>(LocalBoxes.omrSubmissions);

  Failure _mapError(Object error, StackTrace stackTrace) =>
      StorageFailure.localWrite(
        diagnostic: 'omr submissions: $error',
        cause: error,
      );
}
