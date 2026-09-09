/// Firestore implementation of [StudentDataSource].
///
/// The only file in `features/students/data` that imports `cloud_firestore`.
/// Not yet exercised against a live project — see
/// `FirestoreSchoolDataSource` for why that is an accepted state right now.
///
/// `createStudent` follows the uniqueness-guard-document transaction pattern
/// from docs/03-firestore-schema.md: reading `student_dedupe/{dedupeKey}`
/// and creating both it and the student document in one transaction, so a
/// second import of the same child collides rather than creating a twin.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/data/service/student_data_source.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

final class FirestoreStudentDataSource implements StudentDataSource {
  FirestoreStudentDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    String? schoolId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    Query<Map<String, dynamic>> q = _firestore.collection(Collections.students);
    if (schoolId != null) {
      q = q.where('schoolId', isEqualTo: schoolId);
    } else if (!scope.isGlobal) {
      // Widest single field this scope can be expressed on directly; a
      // school-level scope with several schools cannot be a single
      // `isEqualTo`, so it goes through `whereIn` on `schoolId` instead.
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
    final String trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      // Prefix-range search (docs/03-firestore-schema.md). The upper bound is
      // named rather than pasted — see [kPrefixSearchUpperBound].
      q = q
          .where('studentName', isGreaterThanOrEqualTo: trimmed)
          .where('studentName', isLessThan: trimmed + kPrefixSearchUpperBound);
    }
    q = q.orderBy('studentName');
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(cursor);
    }
    q = q.limit(pageSize);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      q.get,
      onError: _mapFirestoreError,
    );
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(
        :final Failure failure,
      ) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok((
        items: value.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  Student.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'studentId': doc.id,
                  }),
            )
            .whereType<Student>()
            .toList(growable: false),
        nextCursor: value.docs.length == pageSize ? value.docs.last : null,
        hasMore: value.docs.length == pageSize,
      )),
    };
  }

  @override
  Future<Result<Student>> getStudent(String studentId) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () =>
              _firestore.collection(Collections.students).doc(studentId).get(),
          onError: _mapFirestoreError,
        );
    return switch (snapshot) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(
        :final Failure failure,
      ) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(:final value) =>
        _decodeStudent(value, studentId),
    };
  }

  Result<Student> _decodeStudent(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String studentId,
  ) {
    final Map<String, dynamic>? data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That student could not be found.',
          entityType: 'student',
          entityId: studentId,
        ),
      );
    }
    final Student? student = Student.tryFromJson(<String, Object?>{
      ...data,
      'studentId': studentId,
    });
    if (student == null) {
      return err(
        UnexpectedFailure(diagnostic: 'student document unreadable: $studentId'),
      );
    }
    return ok(student);
  }

  @override
  Future<Result<Student>> createStudent(Student student) async {
    final DocumentReference<Map<String, dynamic>> dedupeRef = _firestore
        .collection(Collections.studentDedupe)
        .doc(student.dedupeKey);
    final DocumentReference<Map<String, dynamic>> studentRef = _firestore
        .collection(Collections.students)
        .doc(student.studentId);

    final Result<Student?> transactionResult = await guardAsync(() {
      return _firestore.runTransaction<Student?>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> existing = await tx.get(
          dedupeRef,
        );
        if (existing.exists) {
          // Signals a duplicate to the caller below without throwing a raw
          // exception through the transaction — `null` here means "the
          // dedupe guard already exists", read back on the outside.
          return null;
        }
        tx.set(dedupeRef, <String, Object?>{
          'studentId': student.studentId,
          'schoolId': student.schoolId,
          'createdAt': student.createdAt.toUtc().toIso8601String(),
        });
        tx.set(studentRef, student.toJson());
        return student;
      });
    }, onError: _mapFirestoreError);

    return switch (transactionResult) {
      FailureResult<Student?>(:final Failure failure) => err(failure),
      Success<Student?>(value: null) => await _duplicateStudentFailure(
        dedupeRef,
        student.dedupeKey,
      ),
      Success<Student?>(:final Student? value) => ok(value!),
    };
  }

  Future<Result<Student>> _duplicateStudentFailure(
    DocumentReference<Map<String, dynamic>> dedupeRef,
    String dedupeKey,
  ) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(dedupeRef.get, onError: _mapFirestoreError);
    final Map<String, dynamic>? data = snapshot.valueOrNull?.data();
    return err(
      DuplicateFailure(
        userMessage: 'This student has already been registered.',
        entityType: 'student',
        entityId: data?['studentId'] as String? ?? dedupeKey,
        details: <String, String>{
          if (data?['schoolId'] is String) 'schoolId': data!['schoolId'] as String,
        },
      ),
    );
  }

  @override
  Future<Result<Student>> updateStudent(Student student) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.students)
        .doc(student.studentId);
    final Result<DocumentSnapshot<Map<String, dynamic>>> existingSnapshot =
        await guardAsync(ref.get, onError: _mapFirestoreError);
    if (existingSnapshot.isFailure) {
      return err(existingSnapshot.failureOrNull!);
    }
    final Object? existingDedupeKey =
        existingSnapshot.valueOrNull?.data()?['dedupeKey'];
    if (existingDedupeKey != null && existingDedupeKey != student.dedupeKey) {
      // The Firestore rule refuses this too (`unchanged('dedupeKey')`); this
      // check gives the caller a specific, immediate reason rather than a
      // bare permission-denied round trip.
      return err(
        const ValidationFailure(
          userMessage: 'A student\'s identity cannot be changed this way.',
          diagnostic: 'attempted dedupeKey change on update',
        ),
      );
    }
    final Result<void> result = await guardAsync(
      () => ref.update(student.toJson()),
      onError: _mapFirestoreError,
    );
    return result.map((_) => student);
  }

  @override
  Future<Result<Set<String>>> existingDedupeKeys(Set<String> dedupeKeys) async {
    final Set<String> found = <String>{};
    // `whereIn` accepts at most 30 values, so a large CSV import is checked
    // in batches rather than one query.
    final List<String> all = dedupeKeys.toList(growable: false);
    for (int i = 0; i < all.length; i += 30) {
      final List<String> batch = all.sublist(
        i,
        (i + 30).clamp(0, all.length),
      );
      final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
        () => _firestore
            .collection(Collections.studentDedupe)
            .where(FieldPath.documentId, whereIn: batch)
            .get(),
        onError: _mapFirestoreError,
      );
      if (snapshot.isFailure) {
        return err(snapshot.failureOrNull!);
      }
      found.addAll(
        snapshot.valueOrNull!.docs.map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) => doc.id,
        ),
      );
    }
    return ok(found);
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
          entityType: 'student',
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
