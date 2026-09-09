/// Firestore implementation of [AssessmentDataSource].
///
/// The only file in `features/assessments/data` that imports
/// `cloud_firestore`. Compiled and unit-testable, but not yet exercised
/// against a live project — the same status the other Firestore data sources
/// ship in.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/data/service/assessment_data_source.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class FirestoreAssessmentDataSource implements AssessmentDataSource {
  FirestoreAssessmentDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<Page<Assessment>>> listAssessments({
    required AccessScope scope,
    String query = '',
    AssessmentStatus? status,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    // An assessment is not itself geographic, so a scoped caller reads their
    // *assignments* first and then the assessments those name. Two queries
    // rather than one, but it is the join the data model actually has —
    // denormalising the school list onto the assessment would put an
    // unbounded, constantly-changing array on a hot document.
    if (!scope.isGlobal) {
      final Result<Set<String>> idsResult = await _visibleAssessmentIds(scope);
      if (idsResult.isFailure) {
        return err(idsResult.failureOrNull!);
      }
      final List<String> ids = idsResult.valueOrNull!.toList(growable: false);
      if (ids.isEmpty) {
        return ok((items: const <Never>[], nextCursor: null, hasMore: false));
      }
      // `whereIn` caps at 30. A caller reaching more than 30 assessments is a
      // wide-scope admin, and the first 30 by id is a poor answer — so this
      // path is bounded deliberately and the remainder is reached by
      // searching, which is what the screen offers.
      Query<Map<String, dynamic>> q = _firestore
          .collection(Collections.assessments)
          .where(FieldPath.documentId, whereIn: ids.take(30).toList());
      if (status != null) {
        q = q.where('status', isEqualTo: status.wireName);
      }
      return _readAssessmentPage(q.limit(pageSize), pageSize);
    }

    Query<Map<String, dynamic>> q = _firestore.collection(
      Collections.assessments,
    );
    if (status != null) {
      q = q.where('status', isEqualTo: status.wireName);
    }
    final String trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      // Prefix-range search (docs/03-firestore-schema.md). The upper bound is
      // named rather than pasted — see [kPrefixSearchUpperBound].
      q = q
          .where('assessmentName', isGreaterThanOrEqualTo: trimmed)
          .where('assessmentName', isLessThan: trimmed + kPrefixSearchUpperBound);
      q = q.orderBy('assessmentName');
    } else {
      q = q.orderBy('createdAt', descending: true);
    }
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(cursor);
    }
    return _readAssessmentPage(q.limit(pageSize), pageSize);
  }

  Future<Result<Set<String>>> _visibleAssessmentIds(AccessScope scope) async {
    final (String field, Set<String> ids) = switch (scope.level) {
      ScopeLevel.global => ('stateId', const <String>{}),
      ScopeLevel.state => ('stateId', scope.stateIds),
      ScopeLevel.district => ('districtId', scope.districtIds),
      ScopeLevel.cluster => ('clusterId', scope.clusterIds),
      ScopeLevel.school => ('schoolId', scope.schoolIds),
    };
    if (ids.isEmpty) {
      return ok(const <String>{});
    }
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.assessmentAssignments)
              .where(field, whereIn: ids.take(30).toList())
              .get(),
          onError: _mapFirestoreError,
        );
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) => <String>{
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in value.docs)
          if (doc.data()['assessmentId'] case final String id) id,
      },
    );
  }

  Future<Result<Page<Assessment>>> _readAssessmentPage(
    Query<Map<String, dynamic>> q,
    int pageSize,
  ) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(q.get, onError: _mapFirestoreError);
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(
        :final Failure failure,
      ) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok((
        items: value.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  Assessment.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'assessmentId': doc.id,
                  }),
            )
            .whereType<Assessment>()
            .toList(growable: false),
        nextCursor: value.docs.length == pageSize ? value.docs.last : null,
        hasMore: value.docs.length == pageSize,
      )),
    };
  }

  @override
  Future<Result<Assessment>> getAssessment(String assessmentId) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.assessments)
              .doc(assessmentId)
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
          userMessage: 'That assessment could not be found.',
          entityType: 'assessment',
          entityId: assessmentId,
        ),
      );
    }
    final Assessment? assessment = Assessment.tryFromJson(<String, Object?>{
      ...data,
      'assessmentId': assessmentId,
    });
    if (assessment == null) {
      return err(
        UnexpectedFailure(
          diagnostic: 'assessment document unreadable: $assessmentId',
        ),
      );
    }
    return ok(assessment);
  }

  @override
  Future<Result<Assessment>> createAssessment(Assessment assessment) async {
    final Result<void> result = await guardAsync(
      () => _firestore
          .collection(Collections.assessments)
          .doc(assessment.assessmentId)
          .set(assessment.toJson()),
      onError: _mapFirestoreError,
    );
    return result.map((_) => assessment);
  }

  @override
  Future<Result<Assessment>> updateAssessment(Assessment assessment) async {
    final Result<void> result = await guardAsync(
      () => _firestore
          .collection(Collections.assessments)
          .doc(assessment.assessmentId)
          .update(assessment.toJson()),
      onError: _mapFirestoreError,
    );
    return result.map((_) => assessment);
  }

  @override
  Future<Result<List<AnswerKey>>> listAnswerKeys(String assessmentId) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.answerKeys)
              .where('assessmentId', isEqualTo: assessmentId)
              .orderBy('version', descending: true)
              .get(),
          onError: _mapFirestoreError,
        );
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) => value.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                AnswerKey.tryFromJson(<String, Object?>{
                  ...doc.data(),
                  'answerKeyId': doc.id,
                }),
          )
          .whereType<AnswerKey>()
          .toList(growable: false),
    );
  }

  @override
  Future<Result<AnswerKey>> saveAnswerKey(AnswerKey key) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.answerKeys)
        .doc(key.answerKeyId);

    // Read-then-write inside a transaction rather than a bare `set`: Critical
    // Rule 7 is that a *published* key is never rewritten, and checking that
    // outside a transaction leaves a window where a concurrent publish lands
    // between the check and the write.
    final Result<AnswerKey?> result = await guardAsync(() {
      return _firestore.runTransaction<AnswerKey?>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> existing = await tx.get(
          ref,
        );
        if (existing.exists && existing.data()?['isPublished'] == true) {
          // `null` signals "already published", read back outside.
          return null;
        }
        tx.set(ref, key.toJson());
        return key;
      });
    }, onError: _mapFirestoreError);

    return switch (result) {
      FailureResult<AnswerKey?>(:final Failure failure) => err(failure),
      Success<AnswerKey?>(value: null) => err(
        ValidationFailure(
          userMessage:
              'Answer key version ${key.version} has been published and '
              'cannot be changed.',
          diagnostic: 'write attempted on published key ${key.answerKeyId}',
        ),
      ),
      Success<AnswerKey?>(:final AnswerKey? value) => ok(value!),
    };
  }

  @override
  Future<Result<AnswerKey>> publishAnswerKey(AnswerKey key) async {
    final DocumentReference<Map<String, dynamic>> keyRef = _firestore
        .collection(Collections.answerKeys)
        .doc(key.answerKeyId);
    final DocumentReference<Map<String, dynamic>> assessmentRef = _firestore
        .collection(Collections.assessments)
        .doc(key.assessmentId);

    final Result<AnswerKey?> result = await guardAsync(() {
      return _firestore.runTransaction<AnswerKey?>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> existing = await tx.get(
          keyRef,
        );
        if (existing.exists && existing.data()?['isPublished'] == true) {
          return null;
        }
        // Both writes in one transaction: an assessment pointing at an
        // unpublished key, or a published key no assessment points at, would
        // each let sheets be scored against something nobody approved.
        tx.set(keyRef, key.toJson());
        tx.update(assessmentRef, <String, Object?>{
          'publishedAnswerKeyVersion': key.version,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
        return key;
      });
    }, onError: _mapFirestoreError);

    return switch (result) {
      FailureResult<AnswerKey?>(:final Failure failure) => err(failure),
      Success<AnswerKey?>(value: null) => err(
        const ValidationFailure(
          userMessage: 'This answer key version is already published.',
          diagnostic: 'double publish',
        ),
      ),
      Success<AnswerKey?>(:final AnswerKey? value) => ok(value!),
    };
  }

  @override
  Future<Result<List<AssessmentAssignment>>> listAssignments(
    String assessmentId,
  ) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.assessmentAssignments)
              .where('assessmentId', isEqualTo: assessmentId)
              .get(),
          onError: _mapFirestoreError,
        );
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) => value.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                AssessmentAssignment.tryFromJson(<String, Object?>{
                  ...doc.data(),
                  'assignmentId': doc.id,
                }),
          )
          .whereType<AssessmentAssignment>()
          .toList(growable: false),
    );
  }

  @override
  Future<Result<AssessmentAssignment>> saveAssignment(
    AssessmentAssignment assignment,
  ) async {
    final Result<void> result = await guardAsync(
      () => _firestore
          .collection(Collections.assessmentAssignments)
          .doc(assignment.assignmentId)
          .set(assignment.toJson()),
      onError: _mapFirestoreError,
    );
    return result.map((_) => assignment);
  }

  @override
  Future<Result<void>> deleteAssignment(String assignmentId) => guardAsync(
    () => _firestore
        .collection(Collections.assessmentAssignments)
        .doc(assignmentId)
        .delete(),
    onError: _mapFirestoreError,
  );

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
          entityType: 'assessment',
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
