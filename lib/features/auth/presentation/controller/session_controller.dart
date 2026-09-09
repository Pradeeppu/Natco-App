/// Owns the session for the whole app.
///
/// The router, the navigation shell and every guarded screen read from here.
/// Sign-in progress is exposed separately from session state so the login form
/// can show a spinner without the router briefly seeing "no session".
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';
import 'package:natco_app/features/auth/domain/repository/auth_repository.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

final class SessionController extends Notifier<SessionState> {
  /// Collaborators are read from `ref` in [build] rather than passed to a
  /// constructor: Riverpod builds a notifier without arguments, and reading
  /// them here is what lets a test override `authRepositoryProvider` and get
  /// the real controller wired to a fake backend.
  late AuthRepository _repository;
  late AppLogger _logger;

  StreamSubscription<String?>? _authStateSubscription;

  @override
  SessionState build() {
    _repository = ref.watch(authRepositoryProvider);
    _logger = ref.watch(loggerProvider);
    _authStateSubscription = _repository.authStateChanges().listen(
      _onBackendAuthStateChanged,
    );
    ref.onDispose(() {
      unawaited(_authStateSubscription?.cancel());
      _authStateSubscription = null;
    });
    // Restore is kicked off rather than awaited: `build` must return
    // synchronously, and the router shows the splash screen while
    // [SessionRestoring] is the state.
    unawaited(restore());
    return const SessionRestoring();
  }

  /// Attempts to restore a session at startup.
  Future<void> restore() async {
    final Result<AuthSession?> result = await _repository.restoreSession();
    state = switch (result) {
      Success<AuthSession?>(value: final AuthSession? session) =>
        session == null
            ? const SessionUnauthenticated()
            : SessionAuthenticated(session),
      FailureResult<AuthSession?>(:final Failure failure) =>
        SessionUnauthenticated(failure: failure),
    };
  }

  /// Signs in. Returns the failure to display inline, or `null` on success.
  ///
  /// The failure is returned rather than only stored in state because the
  /// login form owns its own error presentation, and because a failed sign-in
  /// must not move the session out of [SessionUnauthenticated] — otherwise the
  /// router would react to a state change that did not happen.
  Future<Failure?> signIn({
    required String email,
    required String password,
  }) async {
    final Result<AuthSession> result = await _repository.signIn(
      email: email,
      password: password,
    );
    return switch (result) {
      Success<AuthSession>(:final AuthSession value) => _authenticate(value),
      FailureResult<AuthSession>(:final Failure failure) => failure,
    };
  }

  Failure? _authenticate(AuthSession session) {
    state = SessionAuthenticated(session);
    return null;
  }

  /// Signs out. Always ends in [SessionUnauthenticated], even if the backend
  /// call failed — the user asked to be signed out on this device.
  Future<void> signOut() async {
    await _repository.signOut();
    state = const SessionUnauthenticated();
  }

  /// Re-checks the profile against the server. Called when connectivity
  /// returns, so a role change or deactivation that happened while the device
  /// was offline takes effect.
  Future<void> revalidate() async {
    if (state is! SessionAuthenticated) {
      return;
    }
    final Result<AuthSession?> result = await _repository.revalidate();
    switch (result) {
      case Success<AuthSession?>(value: final AuthSession? session):
        if (session != null) {
          state = SessionAuthenticated(session);
        } else {
          state = const SessionUnauthenticated();
        }
      case FailureResult<AuthSession?>(:final Failure failure):
        if (failure.isRetryable) {
          // Transient: keep the session, try again on the next reconnect.
          _logger.info(
            'session_revalidate_deferred',
            fields: <String, Object?>{'code': failure.code.name},
          );
          return;
        }
        state = SessionUnauthenticated(failure: failure);
    }
  }

  /// Requests a password-reset email.
  Future<Failure?> requestPasswordReset(String email) async {
    final Result<void> result = await _repository.requestPasswordReset(email);
    return result.failureOrNull;
  }

  /// Reacts to a sign-out the backend initiated — a revoked token, a deleted
  /// account. The app must not keep showing a session the backend has ended.
  void _onBackendAuthStateChanged(String? userId) {
    final SessionState current = state;
    if (userId == null && current is SessionAuthenticated) {
      _logger.info(
        'session_ended_by_backend',
        fields: <String, Object?>{'userId': current.session.user.userId},
      );
      state = const SessionUnauthenticated();
    }
  }
}
