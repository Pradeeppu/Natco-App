/// Authentication use cases, as seen by the presentation layer.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';

abstract interface class AuthRepository {
  /// Restores a session at startup.
  ///
  /// Tries the server first when reachable, so a revoked role or a
  /// deactivated account takes effect immediately; falls back to the cached
  /// session when offline, provided it has not expired. Returns `null` when
  /// there is no usable session, which sends the user to the login screen.
  Future<Result<AuthSession?>> restoreSession();

  /// Signs in and caches the resulting session.
  Future<Result<AuthSession>> signIn({
    required String email,
    required String password,
  });

  /// Signs out and clears the cached session.
  Future<Result<void>> signOut();

  /// Re-reads the profile from the server and refreshes the cached session.
  ///
  /// Called when connectivity returns. A user whose role changed while the
  /// device was offline is updated here, or signed out if deactivated.
  Future<Result<AuthSession?>> revalidate();

  /// Requests a password-reset email.
  Future<Result<void>> requestPasswordReset(String email);

  /// Emits when the backend reports a sign-in or sign-out this app did not
  /// initiate — a revoked token, a deleted account.
  Stream<String?> authStateChanges();
}
