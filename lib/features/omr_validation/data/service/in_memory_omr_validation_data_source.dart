/// In-memory [OmrValidationDataSource]. Backs demo mode and tests.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/data/service/omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';

final class InMemoryOmrValidationDataSource implements OmrValidationDataSource {
  InMemoryOmrValidationDataSource({
    List<OmrSubmission> submissions = const <OmrSubmission>[],
    List<OmrAnswer> answers = const <OmrAnswer>[],
  }) : _submissions = <String, OmrSubmission>{
         for (final OmrSubmission s in submissions) s.omrId: s,
       },
       _answers = <String, List<OmrAnswer>>{
         for (final OmrSubmission s in submissions)
           s.omrId: answers
               .where((OmrAnswer a) => a.omrId == s.omrId)
               .toList()
             ..sort(
               (OmrAnswer a, OmrAnswer b) =>
                   a.questionNumber.compareTo(b.questionNumber),
             ),
       };

  final Map<String, OmrSubmission> _submissions;
  final Map<String, List<OmrAnswer>> _answers;
  final Map<String, List<OmrValidationRecord>> _history =
      <String, List<OmrValidationRecord>>{};

  @override
  Future<Result<Page<OmrSubmission>>> listQueue({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final String needle = query.trim().toLowerCase();
    final List<OmrSubmission> matching =
        _submissions.values
            .where((OmrSubmission s) => s.needsValidation)
            .where(
              (OmrSubmission s) => scope.covers(
                ScopeTarget(
                  stateId: s.stateId,
                  districtId: s.districtId,
                  clusterId: s.clusterId,
                  schoolId: s.schoolId,
                ),
              ),
            )
            .where(
              (OmrSubmission s) =>
                  needle.isEmpty || s.omrId.toLowerCase().contains(needle),
            )
            .toList()
          ..sort(
            (OmrSubmission a, OmrSubmission b) =>
                a.capturedAt.compareTo(b.capturedAt),
          );

    final int offset = cursor is int ? cursor : 0;
    final int end = (offset + pageSize).clamp(0, matching.length);
    final List<OmrSubmission> items = offset >= matching.length
        ? const <OmrSubmission>[]
        : matching.sublist(offset, end);
    final bool hasMore = end < matching.length;
    return ok((
      items: items,
      nextCursor: hasMore ? end : null,
      hasMore: hasMore,
    ));
  }

  @override
  Future<Result<OmrSubmission>> getSubmission(String omrId) async {
    final OmrSubmission? submission = _submissions[omrId];
    if (submission == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That OMR sheet could not be found.',
          entityType: 'omr_submission',
          entityId: omrId,
        ),
      );
    }
    return ok(submission);
  }

  @override
  Future<Result<List<OmrSubmission>>> listCapturedOrProcessing() async => ok(
    _submissions.values
        .where(
          (OmrSubmission s) =>
              s.processingStatus == OmrProcessingStatus.captured ||
              s.processingStatus == OmrProcessingStatus.processing,
        )
        .toList(growable: false),
  );

  @override
  Future<Result<Page<OmrSubmission>>> listSubmissionsForAssessment({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final List<OmrSubmission> matching =
        _submissions.values
            .where((OmrSubmission s) => s.assessmentId == assessmentId)
            .where(
              (OmrSubmission s) => scope.covers(
                ScopeTarget(
                  stateId: s.stateId,
                  districtId: s.districtId,
                  clusterId: s.clusterId,
                  schoolId: s.schoolId,
                ),
              ),
            )
            .toList()
          ..sort(
            (OmrSubmission a, OmrSubmission b) =>
                a.capturedAt.compareTo(b.capturedAt),
          );

    final int offset = cursor is int ? cursor : 0;
    final int end = (offset + pageSize).clamp(0, matching.length);
    final List<OmrSubmission> items = offset >= matching.length
        ? const <OmrSubmission>[]
        : matching.sublist(offset, end);
    final bool hasMore = end < matching.length;
    return ok((
      items: items,
      nextCursor: hasMore ? end : null,
      hasMore: hasMore,
    ));
  }

  @override
  Future<Result<List<OmrAnswer>>> getAnswers(String omrId) async =>
      ok(List<OmrAnswer>.unmodifiable(_answers[omrId] ?? const <OmrAnswer>[]));

  @override
  Future<Result<List<OmrValidationRecord>>> getValidationHistory(
    String omrId,
  ) async => ok(
    List<OmrValidationRecord>.unmodifiable(
      _history[omrId] ?? const <OmrValidationRecord>[],
    ),
  );

  @override
  Future<Result<OmrAnswer>> saveAnswer(OmrAnswer answer) async {
    final List<OmrAnswer> forSheet = _answers.putIfAbsent(
      answer.omrId,
      () => <OmrAnswer>[],
    );
    final int index = forSheet.indexWhere(
      (OmrAnswer a) => a.omrAnswerId == answer.omrAnswerId,
    );
    if (index >= 0) {
      forSheet[index] = answer;
    } else {
      forSheet
        ..add(answer)
        ..sort(
          (OmrAnswer a, OmrAnswer b) =>
              a.questionNumber.compareTo(b.questionNumber),
        );
    }
    return ok(answer);
  }

  @override
  Future<Result<void>> appendValidationRecord(
    OmrValidationRecord record,
  ) async {
    _history.putIfAbsent(record.omrId, () => <OmrValidationRecord>[]).add(record);
    return ok(null);
  }

  @override
  Future<Result<OmrSubmission>> saveSubmission(OmrSubmission submission) async {
    if (!_submissions.containsKey(submission.omrId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That OMR sheet could not be found.',
          entityType: 'omr_submission',
          entityId: submission.omrId,
        ),
      );
    }
    _submissions[submission.omrId] = submission;
    return ok(submission);
  }
}
