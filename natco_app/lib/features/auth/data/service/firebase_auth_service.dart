/// Firebase implementation of [AuthService].
///
/// This is the only file in the auth feature that imports `firebase_auth` or
/// `cloud_firestore`. Everything above it works with domain types.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/data/service/auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';

final class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    required fb.FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required AppLogger logger,
  }) : _auth = auth,
       _firestore = firestore,
       _logger = logger;

  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AppLogger _logger;

  @override
  Future<Result<AppUser?>> currentUser() async {
    final fb.User? user = _auth.currentUser;
    if (user == null) {
      return ok(null);
    }
    final Result<AppUser> profile = await refreshUser(user.uid);
    return profile.map<AppUser?>((AppUser value) => value);
  }

  @override
  Future<Result<AppUser>> signIn({
    required String email,
    required String password,
  }) async {
    final Result<fb.UserCredential> credential = await guardAsync(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
      onError: _mapAuthError,
    );
    return switch (credential) {
      FailureResult<fb.UserCredential>(:final Failure failure) => err(failure),
      Success<fb.UserCredential>(:final fb.UserCredential value) =>
        await _loadProfile(value.user?.uid),
    };
  }

  Future<Result<AppUser>> _loadProfile(String? uid) async {
    if (uid == null) {
      return err(
        const UnexpectedFailure(diagnostic: 'sign-in succeeded without a uid'),
      );
    }
    final Result<AppUser> profile = await refreshUser(uid);
    // A signed-in credential with a deactivated or unusable profile must not
    // leave a live Firebase session behind: the next silent restore would
    // resurrect it.
    if (profile.isFailure) {
      await guardAsync(_auth.signOut);
    }
    return profile;
  }

  @override
  Future<Result<AppUser>> refreshUser(String userId) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore.collection(Collections.users).doc(userId).get(),
          onError: _mapFirestoreError,
        );
    return switch (snapshot) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(
        :final Failure failure,
      ) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(
        :final DocumentSnapshot<Map<String, dynamic>> value,
      ) =>
        _mapProfile(userId, value),
    };
  }

  Result<AppUser> _mapProfile(
    String userId,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic>? data = snapshot.data();
    if (!snapshot.exists || data == null) {
      // An Auth account with no profile document cannot be authorised: there
      // is no role and no scope to authorise against.
      _logger.error(
        'auth_profile_missing',
        fields: <String, Object?>{'userId': userId},
      );
      return err(
        const AuthFailure(
          code: FailureCode.accountDisabled,
          userMessage:
              'Your account is not fully set up. Please contact your '
              'administrator.',
          diagnostic: 'users document missing',
        ),
      );
    }
    final AppUser? user = AppUser.tryFromJson(<String, Object?>{
      ...data,
      'userId': userId,
    });
    if (user == null) {
      _logger.error(
        'auth_profile_unreadable',
        fields: <String, Object?>{
          'userId': userId,
          'role': data['role'],
          'scopeLevel': (data['scope'] as Map<String, dynamic>?)?['level'],
        },
      );
      return err(
        const AuthFailure(
          code: FailureCode.accountDisabled,
          userMessage:
              'Your account settings could not be read. Please contact your '
              'administrator.',
          diagnostic: 'role or scope unresolvable',
        ),
      );
    }
    if (!user.isActive) {
      return err(AuthFailure.accountDisabled(diagnostic: 'isActive=false'));
    }
    return ok(user);
  }

  @override
  Future<Result<void>> signOut() =>
      guardAsync(_auth.signOut, onError: _mapAuthError);

  @override
  Future<Result<void>> refreshCredentials() => guardAsync(() async {
    await _auth.currentUser?.getIdToken(true);
  }, onError: _mapAuthError);

  @override
  Future<Result<void>> sendPasswordReset(String email) async {
    final Result<void> result = await guardAsync(
      () => _auth.sendPasswordResetEmail(email: email.trim()),
      onError: _mapAuthError,
    );
    // An unknown address must not be distinguishable from a known one, or the
    // endpoint becomes an account-enumeration oracle.
    if (result.failureOrNull?.code == FailureCode.invalidCredentials) {
      return ok(null);
    }
    return result;
  }

  @override
  Stream<String?> authStateChanges() =>
      _auth.authStateChanges().map((fb.User? user) => user?.uid);

  Failure _mapAuthError(Object error, StackTrace stackTrace) {
    if (error is fb.FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' ||
        'wrong-password' ||
        'user-not-found' ||
        'invalid-credential' => AuthFailure.invalidCredentials(
          diagnostic: error.code,
        ),
        'user-disabled' => AuthFailure.accountDisabled(diagnostic: error.code),
        'too-many-requests' => AuthFailure.tooManyAttempts(
          diagnostic: error.code,
        ),
        'network-request-failed' => NetworkFailure.unreachable(
          diagnostic: error.code,
          cause: error,
        ),
        _ => UnexpectedFailure(
          diagnostic: 'FirebaseAuthException ${error.code}',
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
