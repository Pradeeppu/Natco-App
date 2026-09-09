/// Firestore implementation of [UserDataSource].
///
/// The only file in `features/users/data` that imports `cloud_firestore`.
/// Compiled and unit-testable, but not yet exercised against a live project —
/// the same status `FirestoreStudentDataSource` and Phase 1's Firebase auth
/// path ship in.
///
/// `createUser` writes only the *account document*. It cannot create the
/// Firebase Auth user, because that needs the Admin SDK and Critical Rule 3
/// forbids putting admin credentials in the APK. A Cloud Function watching
/// this collection creates the Auth user, sets the custom claims from `role`
/// and `scope`, and sends the invitation — which is also what keeps claims
/// server-authoritative (docs/04-security-model.md).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/users/data/service/user_data_source.dart';

final class FirestoreUserDataSource implements UserDataSource {
  FirestoreUserDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<Page<AppUser>>> listUsers({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    Query<Map<String, dynamic>> q = _firestore.collection(Collections.users);

    if (!scope.isGlobal) {
      // Matches the denormalised ancestry `UserRepositoryImpl` writes into
      // every account's scope. `scope.<level>Ids` is an array on the document,
      // so `arrayContainsAny` asks "does this person work anywhere I do".
      final (String field, Set<String> ids) = switch (scope.level) {
        ScopeLevel.global => ('scope.stateIds', const <String>{}),
        ScopeLevel.state => ('scope.stateIds', scope.stateIds),
        ScopeLevel.district => ('scope.districtIds', scope.districtIds),
        ScopeLevel.cluster => ('scope.clusterIds', scope.clusterIds),
        ScopeLevel.school => ('scope.schoolIds', scope.schoolIds),
      };
      if (ids.isEmpty) {
        return ok((items: const <Never>[], nextCursor: null, hasMore: false));
      }
      q = q.where(field, arrayContainsAny: ids.take(30).toList());
    }

    final String trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      // Prefix-range search (docs/03-firestore-schema.md). The upper bound is
      // named rather than pasted — see [kPrefixSearchUpperBound].
      q = q
          .where('displayName', isGreaterThanOrEqualTo: trimmed)
          .where('displayName', isLessThan: trimmed + kPrefixSearchUpperBound);
    }
    q = q.orderBy('displayName');
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(cursor);
    }
    q = q.limit(pageSize);

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
                  AppUser.tryFromJson(<String, Object?>{
                    ...doc.data(),
                    'userId': doc.id,
                  }),
            )
            // A document this build cannot fully read is dropped rather than
            // partially trusted, matching `AppUser.tryFromJson`'s contract:
            // an account whose role or scope is unreadable must not appear as
            // an account with *some* reach.
            .whereType<AppUser>()
            .toList(growable: false),
        nextCursor: value.docs.length == pageSize ? value.docs.last : null,
        hasMore: value.docs.length == pageSize,
      )),
    };
  }

  @override
  Future<Result<AppUser>> getUser(String userId) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore.collection(Collections.users).doc(userId).get(),
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
          userMessage: 'That user could not be found.',
          entityType: 'user',
          entityId: userId,
        ),
      );
    }
    final AppUser? user = AppUser.tryFromJson(<String, Object?>{
      ...data,
      'userId': userId,
    });
    if (user == null) {
      return err(
        UnexpectedFailure(diagnostic: 'user document unreadable: $userId'),
      );
    }
    return ok(user);
  }

  @override
  Future<Result<AppUser>> createUser(AppUser user) async {
    final String email = user.email.trim().toLowerCase();
    final DocumentReference<Map<String, dynamic>> guardRef = _firestore
        .collection(Collections.userEmail)
        .doc(email);
    final DocumentReference<Map<String, dynamic>> userRef = _firestore
        .collection(Collections.users)
        .doc(user.userId);

    final Result<AppUser?> transactionResult = await guardAsync(() {
      return _firestore.runTransaction<AppUser?>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> existing = await tx.get(
          guardRef,
        );
        if (existing.exists) {
          // `null` means "the email guard already exists", read back outside
          // the transaction rather than thrown through it.
          return null;
        }
        tx.set(guardRef, <String, Object?>{
          'userId': user.userId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
        tx.set(userRef, user.toJson());
        return user;
      });
    }, onError: _mapFirestoreError);

    return switch (transactionResult) {
      FailureResult<AppUser?>(:final Failure failure) => err(failure),
      Success<AppUser?>(value: null) => await _duplicateEmailFailure(
        guardRef,
        email,
      ),
      Success<AppUser?>(:final AppUser? value) => ok(value!),
    };
  }

  Future<Result<AppUser>> _duplicateEmailFailure(
    DocumentReference<Map<String, dynamic>> guardRef,
    String email,
  ) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(guardRef.get, onError: _mapFirestoreError);
    final Map<String, dynamic>? data = snapshot.valueOrNull?.data();
    return err(
      DuplicateFailure(
        userMessage:
            'An account already exists for this email address. Ask a Super '
            'Admin to change its role or schools instead of creating a second '
            'one.',
        entityType: 'user',
        entityId: data?['userId'] as String? ?? email,
      ),
    );
  }

  @override
  Future<Result<AppUser>> updateUser(AppUser user) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.users)
        .doc(user.userId);
    final Result<DocumentSnapshot<Map<String, dynamic>>> existing =
        await guardAsync(ref.get, onError: _mapFirestoreError);
    if (existing.isFailure) {
      return err(existing.failureOrNull!);
    }
    final Object? storedEmail = existing.valueOrNull?.data()?['email'];
    if (storedEmail is String &&
        storedEmail.trim().toLowerCase() != user.email.trim().toLowerCase()) {
      // The rule refuses this too; checking here gives an immediate, specific
      // reason instead of a bare permission-denied round trip.
      return err(
        const ValidationFailure(
          userMessage:
              'An email address cannot be changed. Deactivate this account and '
              'create a new one.',
          diagnostic: 'attempted email change on update',
        ),
      );
    }

    // `claimsVersion` is bumped here so the holder's client can tell its ID
    // token is stale and force a refresh, rather than waiting up to an hour
    // for expiry while carrying a role or scope that has been revoked
    // (docs/04-security-model.md).
    final Map<String, Object?> payload = <String, Object?>{
      ...user.toJson(),
      'claimsVersion': FieldValue.increment(1),
    };
    final Result<void> result = await guardAsync(
      () => ref.update(payload),
      onError: _mapFirestoreError,
    );
    return result.map((_) => user.copyWith(claimsVersion: user.claimsVersion + 1));
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
          entityType: 'user',
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
