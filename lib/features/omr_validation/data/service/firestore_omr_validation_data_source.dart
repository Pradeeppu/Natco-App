/// Firestore implementation of [OmrValidationDataSource].
///
/// The only file in `features/omr_validation/data` that imports
/// `cloud_firestore`. Compiled and unit-testable, but not yet exercised
/// against a live project — the same status every other Firestore data
/// source in this app ships in.
///
/// `saveAnswer`'s update is deliberately narrow: `firebase/firestore.rules`
/// refuses a write to `omr_answers` that changes `omrId`, `questionNumber`,
/// `machineAnswer`, `machineConfidence`, `machineStatus` or `optionScores`,
/// and refuses `isCorrect`/`marks` from anyone but the scoring function. This
/// method sends the whole `OmrAnswer.toJson()` because the entity itself
/// guarantees — via `withValidation` — that those fields are unchanged; the
/// rule is what makes that guarantee true against a client that skips the
/// entity altogether.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/data/service/omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';

final class FirestoreOmrValidationDataSource implements OmrValidationDataSource {
  FirestoreOmrValidationDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<Page<OmrSubmission>>> listQueue({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    Query<Map<String, dynamic>> q = _firestore
        .collection(Collections.omrSubmissions)
        .where('validationStatus', whereIn: <String>['PENDING', 'IN_PROGRESS']);

    if (!scope.isGlobal) {
      final (String field, Set<String> ids) = switch (scope.level) {
        ScopeLevel.global => ('stateId', const <String>{}),
        ScopeLevel.state => ('stateId', scope.stateIds),
        ScopeLevel.district => ('districtId', scope.districtIds),
        ScopeLevel.cluster => ('clusterId', scope.clusterIds),
        ScopeLevel.school => ('schoolId', scope.schoolIds),
      };
      if (ids.isEmpty) {
        return ok((items: const <Never>[], nextCursor: null, hasMore: false));
      }
      q = q.where(field, whereIn: ids.take(30).toList());
    }

    q = q.orderBy('capturedAt');
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(cursor);
    }
    q = q.limit(pageSize);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(q.get, onError: _mapFirestoreError);
    final Result<Page<OmrSubmission>> page = switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final Failure failure) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok((
        items: value.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  OmrSubmission.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'omrId': doc.id,
                  }),
            )
            .whereType<OmrSubmission>()
            .toList(growable: false),
        nextCursor: value.docs.length == pageSize ? value.docs.last : null,
        hasMore: value.docs.length == pageSize,
      )),
    };
    // The search-by-id filter has no efficient Firestore query shape (an
    // omrId prefix range would need its own index and this screen is a short
    // queue, not a paged directory), so it is applied to the page already
    // fetched — acceptable here specifically because the *scope* filter above
    // already bounds the query to a small, already-narrow set of rows, unlike
    // the master-data lists where this exact shortcut is refused.
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return page;
    }
    return page.map(
      (Page<OmrSubmission> p) => (
        items: p.items
            .where((OmrSubmission s) => s.omrId.toLowerCase().contains(needle))
            .toList(growable: false),
        nextCursor: p.nextCursor,
        hasMore: p.hasMore,
      ),
    );
  }

  @override
  Future<Result<OmrSubmission>> getSubmission(String omrId) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.omrSubmissions)
              .doc(omrId)
              .get(),
          onError: _mapFirestoreError,
        );
    if (snapshot.isFailure) {
      return err(snapshot.failureOrNull!);
    }
    final DocumentSnapshot<Map<String, dynamic>> doc = snapshot.valueOrNull!;
    final Map<String, dynamic>? data = doc.data();
    if (!doc.exists || data == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That OMR sheet could not be found.',
          entityType: 'omr_submission',
          entityId: omrId,
        ),
      );
    }
    final OmrSubmission? submission = OmrSubmission.tryFromJson(<String, Object?>{
      ...data,
      'omrId': omrId,
    });
    if (submission == null) {
      return err(
        UnexpectedFailure(diagnostic: 'submission document unreadable: $omrId'),
      );
    }
    return ok(submission);
  }

  /// A real deployment should never need this method to run against
  /// Firestore at all: reconciliation is inherently about what *this device*
  /// captured and never finished, which belongs in local storage
  /// (`HiveAssessmentSessionStore` is the model to follow), not a remote
  /// query. It exists here only because phase 5's capture flow — and the
  /// local OMR store that comes with it — has not landed yet, so there is
  /// nowhere else for this query to run, and is compiled but not yet
  /// exercised, the same status every other Firestore data source in this
  /// app ships in.
  ///
  /// Deliberately has no `capturedBy` filter — this class holds no current-
  /// user id to filter by, and none of its other methods need one either.
  /// The query is unscoped on the client; `firebase/firestore.rules`'
  /// `omr_submissions` rule is what actually bounds a real caller to their
  /// own scope or their own captures, per document, the same way every
  /// `list` query in this app relies on the rule rather than a client
  /// filter for enforcement.
  @override
  Future<Result<List<OmrSubmission>>> listCapturedOrProcessing() async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      () => _firestore
          .collection(Collections.omrSubmissions)
          .where(
            'processingStatus',
            whereIn: <String>['CAPTURED', 'PROCESSING'],
          )
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
                  OmrSubmission.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'omrId': doc.id,
                  }),
            )
            .whereType<OmrSubmission>()
            .toList(growable: false),
      ),
    };
  }

  @override
  Future<Result<Page<OmrSubmission>>> listSubmissionsForAssessment({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    Query<Map<String, dynamic>> q = _firestore
        .collection(Collections.omrSubmissions)
        .where('assessmentId', isEqualTo: assessmentId);

    if (!scope.isGlobal) {
      final (String field, Set<String> ids) = switch (scope.level) {
        ScopeLevel.global => ('stateId', const <String>{}),
        ScopeLevel.state => ('stateId', scope.stateIds),
        ScopeLevel.district => ('districtId', scope.districtIds),
        ScopeLevel.cluster => ('clusterId', scope.clusterIds),
        ScopeLevel.school => ('schoolId', scope.schoolIds),
      };
      if (ids.isEmpty) {
        return ok((items: const <Never>[], nextCursor: null, hasMore: false));
      }
      q = q.where(field, whereIn: ids.take(30).toList());
    }

    q = q.orderBy('capturedAt');
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(cursor);
    }
    q = q.limit(pageSize);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(q.get, onError: _mapFirestoreError);
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final Failure failure) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok((
        items: value.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  OmrSubmission.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'omrId': doc.id,
                  }),
            )
            .whereType<OmrSubmission>()
            .toList(growable: false),
        nextCursor: value.docs.length == pageSize ? value.docs.last : null,
        hasMore: value.docs.length == pageSize,
      )),
    };
  }

  @override
  Future<Result<List<OmrAnswer>>> getAnswers(String omrId) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      () => _firestore
          .collection(Collections.omrAnswers)
          .where('omrId', isEqualTo: omrId)
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
                  OmrAnswer.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'omrAnswerId': doc.id,
                  }),
            )
            .whereType<OmrAnswer>()
            .toList(growable: false),
      ),
    };
  }

  @override
  Future<Result<List<OmrValidationRecord>>> getValidationHistory(
    String omrId,
  ) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      () => _firestore
          .collection(Collections.omrValidations)
          .where('omrId', isEqualTo: omrId)
          .orderBy('validatedAt')
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
                  OmrValidationRecord.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'validationId': doc.id,
                  }),
            )
            .whereType<OmrValidationRecord>()
            .toList(growable: false),
      ),
    };
  }

  @override
  Future<Result<OmrAnswer>> saveAnswer(OmrAnswer answer) async {
    final Result<void> result = await guardAsync(
      () => _firestore
          .collection(Collections.omrAnswers)
          .doc(answer.omrAnswerId)
          .update(answer.toJson()),
      onError: _mapFirestoreError,
    );
    return result.map((_) => answer);
  }

  @override
  Future<Result<void>> appendValidationRecord(
    OmrValidationRecord record,
  ) => guardAsync(
    () => _firestore
        .collection(Collections.omrValidations)
        .doc(record.validationId)
        .set(record.toJson()),
    onError: _mapFirestoreError,
  );

  @override
  Future<Result<OmrSubmission>> saveSubmission(OmrSubmission submission) async {
    final Result<void> result = await guardAsync(
      () => _firestore
          .collection(Collections.omrSubmissions)
          .doc(submission.omrId)
          .update(submission.toJson()),
      onError: _mapFirestoreError,
    );
    return result.map((_) => submission);
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
        'not-found' => const NotFoundFailure(
          userMessage: 'That record could not be found.',
          entityType: 'omr_submission',
          entityId: 'unknown',
        ),
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
