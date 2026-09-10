/// Backend-swappable raw storage for submissions, answers and the
/// validation log.
///
/// Mirrors `StudentDataSource`: CRUD and paged queries only. Policy and audit
/// logging live once in `OmrValidationRepositoryImpl` rather than being
/// reimplemented per backend.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';

abstract interface class OmrValidationDataSource {
  Future<Result<Page<OmrSubmission>>> listQueue({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<OmrSubmission>> getSubmission(String omrId);

  /// Every submission in `CAPTURED` or `PROCESSING`, with no scope filter —
  /// see `OmrValidationRepository.listCapturedOrProcessing` for why.
  Future<Result<List<OmrSubmission>>> listCapturedOrProcessing();

  Future<Result<Page<OmrSubmission>>> listSubmissionsForAssessment({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<List<OmrAnswer>>> getAnswers(String omrId);

  Future<Result<List<OmrValidationRecord>>> getValidationHistory(String omrId);

  /// Replaces one answer wholesale. The caller (`OmrValidationRepositoryImpl`)
  /// is what guarantees the replacement only ever came from
  /// `OmrAnswer.withValidation` or `withScore` — this layer trusts what it is
  /// given, exactly like every other data source in the app.
  Future<Result<OmrAnswer>> saveAnswer(OmrAnswer answer);

  Future<Result<void>> appendValidationRecord(OmrValidationRecord record);

  Future<Result<OmrSubmission>> saveSubmission(OmrSubmission submission);
}
