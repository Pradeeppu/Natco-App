/// Orchestrates the auth backend and the local session cache.
///
/// The two interesting behaviours live here rather than in a controller:
///
/// * **Restore prefers the server.** When the device is reachable, startup
///   re-reads the profile so a revoked role or deactivated account takes
///   effect at once. Only when unreachable does it fall back to the cache.
/// * **Expiry is measured from the last verification**, not from sign-in, so a
///   device that reconnects daily stays usable indefinitely while one that
///   never reconnects stops after the configured window.
library;

import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/data/service/auth_service.dart';
import 'package:natco_app/features/auth/data/store/session_store.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';
import 'package:natco_app/features/auth/domain/repository/auth_repository.dart';

final class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthService authService,
    required SessionStore sessionStore,
    required ConnectivityService connectivity,
    required DeviceInfoService deviceInfo,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required AppLogger logger,
    required AppConfig config,
  }) : _authService = authService,
       _sessionStore = sessionStore,
       _connectivity = connectivity,
       _deviceInfo = deviceInfo,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _logger = logger,
       _config = config;

  final AuthService _authService;
  final SessionStore _sessionStore;
  final ConnectivityService _connectivity;
  final DeviceInfoService _deviceInfo;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final AppLogger _logger;
  final AppConfig _config;

  @override
  Future<Result<AuthSession?>> restoreSession() async {
    final Result<AuthSession?> cached = await _sessionStore.read();
    // A failure to read local storage is not a reason to sign the user out of
    // a working session, but it is a reason to log loudly.
    if (cached.isFailure) {
      _logger.error(
        'session_restore_read_failed',
        fields: <String, Object?>{'code': cached.failureOrNull?.code.name},
      );
    }
    final AuthSession? cachedSession = cached.valueOrNull;

    final ConnectionStatus status = await _connectivity.current();
    if (status.isReachable) {
      final Result<AuthSession?> online = await _restoreFromServer(
        cachedSession,
      );
      // Fall through to the cache only when the server could not be consulted;
      // a definitive server answer (including "deactivated") wins.
      if (online.isSuccess || !(online.failureOrNull?.isRetryable ?? false)) {
        return online;
      }
      _logger.warning(
        'session_restore_server_unavailable',
        fields: <String, Object?>{'code': online.failureOrNull?.code.name},
      );
    }
    return _restoreFromCache(cachedSession);
  }

  Future<Result<AuthSession?>> _restoreFromServer(
    AuthSession? cachedSession,
  ) async {
    final Result<AppUser?> current = await _authService.currentUser();
    return switch (current) {
      FailureResult<AppUser?>(:final Failure failure) =>
        _handleServerRestoreFailure(failure),
      Success<AppUser?>(value: final AppUser? user) =>
        user == null
            ? await _clearAndReturnNoSession()
            : await _persistVerifiedSession(user, cachedSession),
    };
  }

  Future<Result<AuthSession?>> _handleServerRestoreFailure(
    Failure failure,
  ) async {
    // A deactivated or unreadable account clears the cache: the point of
    // checking the server is that this answer sticks.
    if (failure.code == FailureCode.accountDisabled) {
      await _sessionStore.clear();
      return err(failure);
    }
    return err<AuthSession?>(failure);
  }

  Future<Result<AuthSession?>> _clearAndReturnNoSession() async {
    await _sessionStore.clear();
    return ok(null);
  }

  Future<Result<AuthSession?>> _persistVerifiedSession(
    AppUser user,
    AuthSession? cachedSession,
  ) async {
    final DateTime now = _clock.nowUtc();
    final AuthSession session = AuthSession(
      user: user,
      establishedAt: cachedSession?.establishedAt ?? now,
      lastVerifiedAt: now,
      origin: SessionOrigin.online,
      deviceId: _deviceInfo.deviceId,
    );
    final Result<void> written = await _sessionStore.write(session);
    if (written.isFailure) {
      // The session is still usable in memory; it just will not survive a
      // restart. Say so in the log rather than failing the sign-in.
      _logger.error(
        'session_cache_write_failed',
        fields: <String, Object?>{'code': written.failureOrNull?.code.name},
      );
    }
    return ok(session);
  }

  Future<Result<AuthSession?>> _restoreFromCache(AuthSession? session) async {
    if (session == null) {
      return ok(null);
    }
    if (!_config.featureFlags.allowOfflineLogin) {
      return err(
        AuthFailure.unauthenticated(diagnostic: 'offline login disabled'),
      );
    }
    if (!session.isValidAt(_clock.nowUtc(), _config.offlineSessionValidity)) {
      await _sessionStore.clear();
      _logger.info(
        'session_offline_expired',
        fields: <String, Object?>{'userId': session.user.userId},
      );
      return err(
        AuthFailure.sessionExpired(diagnostic: 'offline validity elapsed'),
      );
    }
    _logger.info(
      'session_restored_offline',
      fields: <String, Object?>{
        'userId': session.user.userId,
        'role': session.user.role.wireName,
      },
    );
    return ok(session.copyWith(origin: SessionOrigin.offlineCache));
  }

  @override
  Future<Result<AuthSession>> signIn({
    required String email,
    required String password,
  }) async {
    final Result<AppUser> result = await _authService.signIn(
      email: email,
      password: password,
    );
    return switch (result) {
      FailureResult<AppUser>(:final Failure failure) =>
        await _recordFailedSignIn(email, failure),
      Success<AppUser>(:final AppUser value) => await _completeSignIn(value),
    };
  }

  Future<Result<AuthSession>> _recordFailedSignIn(
    String email,
    Failure failure,
  ) async {
    // The audit entry records that a sign-in failed and why, but never the
    // address that was tried: an audit log full of typo'd email addresses is
    // personal data we have no use for (requirement section 55).
    await _auditSink.record(
      AuditEvent(
        auditId: _idGenerator.newId(),
        userId: 'anonymous',
        role: 'NONE',
        action: AuditAction.loginFailed,
        entityType: 'session',
        entityId: 'anonymous',
        timestamp: _clock.nowUtc(),
        deviceId: _deviceInfo.deviceId,
        appVersion: _deviceInfo.appVersion,
        newValue: <String, Object?>{'reason': failure.code.name},
      ),
    );
    _logger.warning(
      'sign_in_failed',
      fields: <String, Object?>{'code': failure.code.name},
    );
    return err(failure);
  }

  Future<Result<AuthSession>> _completeSignIn(AppUser user) async {
    final DateTime now = _clock.nowUtc();
    final AuthSession session = AuthSession(
      user: user,
      establishedAt: now,
      lastVerifiedAt: now,
      origin: SessionOrigin.online,
      deviceId: _deviceInfo.deviceId,
    );
    final Result<void> written = await _sessionStore.write(session);
    if (written.isFailure) {
      _logger.error(
        'session_cache_write_failed',
        fields: <String, Object?>{'code': written.failureOrNull?.code.name},
      );
    }
    await _auditSink.record(
      AuditEvent(
        auditId: _idGenerator.newId(),
        userId: user.userId,
        role: user.role.wireName,
        action: AuditAction.loginSucceeded,
        entityType: 'session',
        entityId: user.userId,
        timestamp: now,
        deviceId: _deviceInfo.deviceId,
        appVersion: _deviceInfo.appVersion,
      ),
    );
    _logger.info(
      'sign_in_succeeded',
      fields: <String, Object?>{
        'userId': user.userId,
        'role': user.role.wireName,
        'scopeLevel': user.scope.level.wireName,
      },
    );
    return ok(session);
  }

  @override
  Future<Result<void>> signOut() async {
    final AuthSession? session = (await _sessionStore.read()).valueOrNull;
    // Local state is cleared first and unconditionally. If the backend call
    // fails, the user is still signed out on this device, which is what they
    // asked for; a sign-out that leaves a usable session behind because the
    // network was down would be a security defect.
    final Result<void> cleared = await _sessionStore.clear();
    if (cleared.isFailure) {
      _logger.error(
        'session_clear_failed',
        fields: <String, Object?>{'code': cleared.failureOrNull?.code.name},
      );
    }
    final Result<void> remote = await _authService.signOut();
    if (session != null) {
      await _auditSink.record(
        AuditEvent(
          auditId: _idGenerator.newId(),
          userId: session.user.userId,
          role: session.user.role.wireName,
          action: AuditAction.logout,
          entityType: 'session',
          entityId: session.user.userId,
          timestamp: _clock.nowUtc(),
          deviceId: _deviceInfo.deviceId,
          appVersion: _deviceInfo.appVersion,
        ),
      );
    }
    if (remote.isFailure) {
      _logger.warning(
        'remote_sign_out_failed',
        fields: <String, Object?>{'code': remote.failureOrNull?.code.name},
      );
    }
    return ok(null);
  }

  @override
  Future<Result<AuthSession?>> revalidate() async {
    final AuthSession? cached = (await _sessionStore.read()).valueOrNull;
    if (cached == null) {
      return ok(null);
    }
    final Result<void> refreshed = await _authService.refreshCredentials();
    if (refreshed.isFailure) {
      _logger.warning(
        'credential_refresh_failed',
        fields: <String, Object?>{'code': refreshed.failureOrNull?.code.name},
      );
    }
    final Result<AppUser> profile = await _authService.refreshUser(
      cached.user.userId,
    );
    return switch (profile) {
      Success<AppUser>(:final AppUser value) => await _persistVerifiedSession(
        value,
        cached,
      ),
      FailureResult<AppUser>(:final Failure failure) =>
        failure.code == FailureCode.accountDisabled ||
                failure.code == FailureCode.notFound
            // A definitive "this account is gone" clears the session.
            ? await _clearAndFail(failure)
            // Anything transient leaves the cached session in place.
            : ok(cached),
    };
  }

  Future<Result<AuthSession?>> _clearAndFail(Failure failure) async {
    await _sessionStore.clear();
    _logger.info(
      'session_invalidated_by_server',
      fields: <String, Object?>{'code': failure.code.name},
    );
    return err<AuthSession?>(failure);
  }

  @override
  Future<Result<void>> requestPasswordReset(String email) =>
      _authService.sendPasswordReset(email);

  @override
  Stream<String?> authStateChanges() => _authService.authStateChanges();
}
