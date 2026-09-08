/// Session state, as the UI and the router see it.
///
/// A sealed hierarchy rather than a single class with nullable fields, so the
/// router's redirect logic is an exhaustive `switch` and a new state cannot be
/// added without every consumer being forced to handle it.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';

sealed class SessionState {
  const SessionState();

  /// The active session, or `null` when there is none.
  AuthSession? get session => switch (this) {
    SessionAuthenticated(:final AuthSession session) => session,
    _ => null,
  };

  /// Authorization for the current user. An unauthenticated state yields an
  /// [Authorization] with no user, which denies everything.
  Authorization get authorization => Authorization(session?.user);

  bool get isRestoring => this is SessionRestoring;

  bool get isAuthenticated => this is SessionAuthenticated;
}

/// Startup is still deciding whether there is a session. The router holds the
/// user on the splash screen rather than flashing the login screen at a user
/// who is in fact signed in.
final class SessionRestoring extends SessionState {
  const SessionRestoring();
}

/// No usable session. [failure] carries the reason when there was one — an
/// expired offline session, a deactivated account — so the login screen can
/// explain why the user is back there.
final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated({this.failure});

  final Failure? failure;

  @override
  bool operator ==(Object other) =>
      other is SessionUnauthenticated && other.failure == failure;

  @override
  int get hashCode => Object.hash(SessionUnauthenticated, failure);
}

/// A signed-in user.
final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.session);

  @override
  final AuthSession session;

  /// Whether this session was restored from the local cache without a server
  /// check. Surfaced in the UI so a user knows their role and assignments may
  /// be out of date.
  bool get isOffline => session.origin == SessionOrigin.offlineCache;

  @override
  bool operator ==(Object other) =>
      other is SessionAuthenticated && other.session == session;

  @override
  int get hashCode => Object.hash(SessionAuthenticated, session);
}
