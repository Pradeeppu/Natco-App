/// The authentication backend boundary.
///
/// Firebase sits behind this interface, and so does the in-memory
/// implementation that demo mode and the test suite use. Swapping to Supabase
/// or anything else means writing one more implementation and changing the
/// composition root — no feature code moves (docs/01-architecture.md).
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';

/// Credentials plus the profile the backend holds for a user.
abstract interface class AuthService {
  /// The currently authenticated user's profile, or `null` if signed out.
  ///
  /// Requires a working connection: this reads the authoritative role and
  /// scope from the server. Offline restoration goes through the session
  /// cache instead.
  Future<Result<AppUser?>> currentUser();

  /// Signs in with email and password and returns the server's profile.
  Future<Result<AppUser>> signIn({
    required String email,
    required String password,
  });

  /// Signs out and clears any backend-held session.
  Future<Result<void>> signOut();

  /// Re-reads the profile for [userId] from the server.
  ///
  /// Used to revalidate a cached session on reconnect: a deactivated user or a
  /// changed role must take effect immediately, not at the cache's expiry.
  Future<Result<AppUser>> refreshUser(String userId);

  /// Forces a fresh ID token so updated custom claims apply now.
  ///
  /// Claim propagation is otherwise bounded by token lifetime, which would let
  /// a revoked role keep working for up to an hour
  /// (docs/04-security-model.md).
  Future<Result<void>> refreshCredentials();

  /// Sends a password-reset email. Succeeds silently for unknown addresses so
  /// the endpoint cannot be used to enumerate accounts.
  Future<Result<void>> sendPasswordReset(String email);

  /// Emits the authenticated user id on sign-in and `null` on sign-out.
  ///
  /// Backend-initiated sign-outs (token revoked, account deleted) arrive here,
  /// which is how the app notices a revocation it did not initiate.
  Stream<String?> authStateChanges();
}
