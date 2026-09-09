/// Firestore implementation of [ResultDataSource].
///
/// The only file in `features/results/data` that imports `cloud_firestore`.
/// `firebase/firestore.rules` denies every client write to `results` —
/// scoring is server-authoritative there, done by a `scoreSubmission` Cloud
/// Function. This class is what a real deployment would need if scoring were
/// ever done from a trusted server context calling through the same
/// repository shape, and it is compiled and unit-testable now for the same
/// reason every other Firestore data source in this app ships un-exercised —
/// but the demo/in-memory path is what every client build actually uses to
/// write a result, matching how `docs/06-offline-sync-strategy.md` describes
/// scoring: "the phone also scores locally so the teacher gets an immediate
/// preview."
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/results/data/service/result_data_source.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';

final class FirestoreResultDataSource implements ResultDataSource {
  FirestoreResultDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<Page<AssessmentResult>>> listResults({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    Query<Map<String, dynamic>> q = _firestore
        .collection(Collections.results)
        .where('assessmentId', isEqualTo: assessmentId)
        .where('supersededBy', isNull: true);

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

    q = q.orderBy('marksObtained', descending: true);
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
                  AssessmentResult.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'resultId': doc.id,
                  }),
            )
            .whereType<AssessmentResult>()
            .toList(growable: false),
        nextCursor: value.docs.length == pageSize ? value.docs.last : null,
        hasMore: value.docs.length == pageSize,
      )),
    };
  }

  @override
  Future<Result<AssessmentResult?>> getCurrentResultForStudent({
    required String assessmentId,
    required String studentId,
  }) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      () => _firestore
          .collection(Collections.results)
          .where('assessmentId', isEqualTo: assessmentId)
          .where('studentId', isEqualTo: studentId)
          .where('supersededBy', isNull: true)
          .limit(1)
          .get(),
      onError: _mapFirestoreError,
    );
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final Failure failure) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok(
        value.docs.isEmpty
            ? null
            : AssessmentResult.tryFromJson(<String, Object?>{
                ...value.docs.first.data(),
                'resultId': value.docs.first.id,
              }),
      ),
    };
  }

  @override
  Future<Result<AssessmentResult?>> getCurrentResultForSubmission(
    String omrId,
  ) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      () => _firestore
          .collection(Collections.results)
          .where('omrId', isEqualTo: omrId)
          .where('supersededBy', isNull: true)
          .limit(1)
          .get(),
      onError: _mapFirestoreError,
    );
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final Failure failure) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok(
        value.docs.isEmpty
            ? null
            : AssessmentResult.tryFromJson(<String, Object?>{
                ...value.docs.first.data(),
                'resultId': value.docs.first.id,
              }),
      ),
    };
  }

  @override
  Future<Result<AssessmentResult>> saveResult(AssessmentResult result) async {
    final Result<void> write = await guardAsync(
      () => _firestore
          .collection(Collections.results)
          .doc(result.resultId)
          .set(result.toJson()),
      onError: _mapFirestoreError,
    );
    return write.map((_) => result);
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
