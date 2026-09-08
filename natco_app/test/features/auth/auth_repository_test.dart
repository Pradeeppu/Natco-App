/// Tests for session restore, sign-in, sign-out and revalidation.
///
/// This is where the offline-login requirement (section 23) and the security
/// requirement that a revoked role take effect promptly meet, and they pull in
/// opposite directions. The tests pin the resolution:
///
/// * reachable  -> the server is authoritative, always re-read;
/// * unreachable -> the cache is used, but only inside its validity window;
/// * a definitive "this account is gone" clears the cache even when it arrives
///   during a restore that could have fallen back to it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/app/config/app_environment.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/data/repository/auth_repository_impl.dart';
import 'package:natco_app/features/auth/data/service/auth_service.dart';
import 'package:natco_app/features/auth/data/store/session_store.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/auth_session.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

final DateTime _t0 = DateTime.utc(2026, 9, 1, 8);

AppUser _teacher({bool isActive = true, UserRole? role}) => AppUser(
  userId: 'u1',
  email: 'teacher@natco.test',
  displayName: 'Suresh Babu',
  role: role ?? UserRole.pstTeacher,
  scope: AccessScope.singleSchool('sch1'),
  isActive: isActive,
);

/// A scriptable [AuthService].
final class _FakeAuthService implements AuthService {
  _FakeAuthService();

  AppUser? signedIn;
  Result<AppUser?>? currentUserResult;
  Result<AppUser>? signInResult;
  Result<AppUser>? refreshUserResult;
  Result<void> refreshCredentialsResult = ok(null);
  Result<void> passwordResetResult = ok(null);

  int currentUserCalls = 0;
  int refreshUserCalls = 0;
  int refreshCredentialsCalls = 0;
  int signOutCalls = 0;

  @override
  Future<Result<AppUser?>> currentUser() async {
    currentUserCalls++;
    return currentUserResult ?? ok<AppUser?>(signedIn);
  }

  @override
  Future<Result<AppUser>> signIn({
    required String email,
    required String password,
  }) async {
    final Result<AppUser>? scripted = signInResult;
    if (scripted != null) {
      signedIn = scripted.valueOrNull;
      return scripted;
    }
    signedIn = _teacher();
    return ok(signedIn!);
  }

  @override
  Future<Result<void>> signOut() async {
    signOutCalls++;
    signedIn = null;
    return ok(null);
  }

  @override
  Future<Result<AppUser>> refreshUser(String userId) async {
    refreshUserCalls++;
    return refreshUserResult ??
        (signedIn != null
            ? ok(signedIn!)
            : err<AppUser>(
                NotFoundFailure(
                  userMessage: 'That account could not be found.',
                  entityType: 'user',
                  entityId: userId,
                ),
              ));
  }

  @override
  Future<Result<void>> refreshCredentials() async {
    refreshCredentialsCalls++;
    return refreshCredentialsResult;
  }

  @override
  Future<Result<void>> sendPasswordReset(String email) async =>
      passwordResetResult;

  @override
  Stream<String?> authStateChanges() => const Stream<String?>.empty();
}

void main() {
  late _FakeAuthService authService;
  late InMemorySessionStore sessionStore;
  late FakeConnectivityService connectivity;
  late InMemoryAuditSink auditSink;
  late FixedClock clock;
  late InMemoryLogSink logSink;
  late AppConfig config;

  AuthRepositoryImpl buildRepository() => AuthRepositoryImpl(
    authService: authService,
    sessionStore: sessionStore,
    connectivity: connectivity,
    deviceInfo: const StaticDeviceInfoService(deviceId: 'device-1'),
    auditSink: auditSink,
    idGenerator: SequentialIdGenerator(),
    clock: clock,
    logger: AppLogger(minimumLevel: LogLevel.debug, sinks: <LogSink>[logSink]),
    config: config,
  );

  /// Seeds a cached session verified at [verifiedAt].
  Future<void> seedCachedSession({
    DateTime? verifiedAt,
    bool isActive = true,
  }) => sessionStore.write(
    AuthSession(
      user: _teacher(isActive: isActive),
      establishedAt: _t0,
      lastVerifiedAt: verifiedAt ?? _t0,
      origin: SessionOrigin.online,
      deviceId: 'device-1',
    ),
  );

  setUp(() {
    authService = _FakeAuthService();
    sessionStore = InMemorySessionStore();
    connectivity = FakeConnectivityService(ConnectionStatus.offline);
    auditSink = InMemoryAuditSink();
    clock = FixedClock(_t0);
    logSink = InMemoryLogSink();
    config = AppConfig.forEnvironment(AppEnvironment.dev);
  });

  group('restoreSession — no cached session', () {
    test('returns no session when offline with nothing cached', () async {
      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('returns no session when online and signed out', () async {
      connectivity.emit(ConnectionStatus.onlineUnmetered);
      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();
      expect(result.valueOrNull, isNull);
      expect(authService.currentUserCalls, 1);
    });
  });

  group('restoreSession — offline', () {
    test('restores a cached session inside its validity window', () async {
      await seedCachedSession();
      clock.advance(const Duration(days: 3));

      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();

      final AuthSession session = result.valueOrNull!;
      expect(session.user.userId, 'u1');
      expect(
        session.origin,
        SessionOrigin.offlineCache,
        reason: 'the UI must be able to say the data may be stale',
      );
      expect(
        authService.currentUserCalls,
        0,
        reason: 'no server call should be attempted while offline',
      );
    });

    test('refuses and clears a session past its validity window', () async {
      await seedCachedSession();
      clock.advance(config.offlineSessionValidity + const Duration(hours: 1));

      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.code, FailureCode.sessionExpired);
      expect(
        (await sessionStore.read()).valueOrNull,
        isNull,
        reason: 'an expired session must not be reusable',
      );
      expect(result.failureOrNull!.userMessage, contains('sign in again'));
    });

    test('refuses a cached session for a deactivated user', () async {
      await seedCachedSession(isActive: false);
      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();
      expect(result.isFailure, isTrue);
    });

    test('refuses to use the cache when offline login is disabled', () async {
      config = config.copyWith(
        featureFlags: config.featureFlags.copyWith(allowOfflineLogin: false),
      );
      await seedCachedSession();
      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.code, FailureCode.unauthenticated);
    });

    test('an interface with no internet is treated as offline', () async {
      // A school Wi-Fi that hands out a lease but has no upstream must not be
      // mistaken for reachability.
      connectivity.emit(ConnectionStatus.interfaceOnly);
      await seedCachedSession();
      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();
      expect(result.valueOrNull!.origin, SessionOrigin.offlineCache);
      expect(authService.currentUserCalls, 0);
    });
  });

  group('restoreSession — online', () {
    setUp(() => connectivity.emit(ConnectionStatus.onlineUnmetered));

    test('re-reads the profile from the server', () async {
      await seedCachedSession();
      authService.signedIn = _teacher();
      clock.advance(const Duration(days: 2));

      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();

      expect(authService.currentUserCalls, 1);
      expect(result.valueOrNull!.origin, SessionOrigin.online);
      expect(
        result.valueOrNull!.lastVerifiedAt,
        clock.nowUtc(),
        reason: 'verification time must advance so the window resets',
      );
    });

    test('picks up a role change made while the device was offline', () async {
      await seedCachedSession();
      authService.signedIn = _teacher(role: UserRole.supervisor);

      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();

      expect(result.valueOrNull!.user.role, UserRole.supervisor);
    });

    test('keeps the original establishedAt across a re-verification', () async {
      await seedCachedSession();
      authService.signedIn = _teacher();
      clock.advance(const Duration(days: 1));

      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();

      expect(result.valueOrNull!.establishedAt, _t0);
    });

    test('falls back to the cache when the server is unreachable', () async {
      await seedCachedSession();
      authService.currentUserResult = err<AppUser?>(
        NetworkFailure.unreachable(),
      );

      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();

      expect(result.valueOrNull!.origin, SessionOrigin.offlineCache);
      expect(
        logSink.records.map((LogRecord r) => r.event),
        contains('session_restore_server_unavailable'),
      );
    });

    test(
      'does not fall back when the server says the account is gone',
      () async {
        // A definitive answer wins over the cache — otherwise a deactivated
        // user keeps working for as long as their cache lasts.
        await seedCachedSession();
        authService.currentUserResult = err<AppUser?>(
          AuthFailure.accountDisabled(),
        );

        final Result<AuthSession?> result = await buildRepository()
            .restoreSession();

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull!.code, FailureCode.accountDisabled);
        expect((await sessionStore.read()).valueOrNull, isNull);
      },
    );

    test('clears the cache when the server reports nobody signed in', () async {
      await seedCachedSession();
      authService.signedIn = null;

      final Result<AuthSession?> result = await buildRepository()
          .restoreSession();

      expect(result.valueOrNull, isNull);
      expect((await sessionStore.read()).valueOrNull, isNull);
    });
  });

  group('signIn', () {
    test('caches the session and records an audit entry', () async {
      final Result<AuthSession> result = await buildRepository().signIn(
        email: 'teacher@natco.test',
        password: 'correct',
      );

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.origin, SessionOrigin.online);
      expect((await sessionStore.read()).valueOrNull, isNotNull);
      expect(auditSink.events.single.action, AuditAction.loginSucceeded);
      expect(auditSink.events.single.userId, 'u1');
      expect(auditSink.events.single.role, 'PST_TEACHER');
      expect(auditSink.events.single.deviceId, 'device-1');
    });

    test('records a failed attempt without storing the address tried', () async {
      authService.signInResult = err<AppUser>(AuthFailure.invalidCredentials());

      final Result<AuthSession> result = await buildRepository().signIn(
        email: 'typo@natco.test',
        password: 'wrong',
      );

      expect(result.isFailure, isTrue);
      final AuditEvent event = auditSink.events.single;
      expect(event.action, AuditAction.loginFailed);
      expect(event.userId, 'anonymous');
      // An audit log full of mistyped email addresses is personal data with no
      // purpose.
      expect(event.toJson().toString(), isNot(contains('typo@natco.test')));
      expect(event.newValue!['reason'], 'invalidCredentials');
    });

    test('does not cache a session for a failed attempt', () async {
      authService.signInResult = err<AppUser>(AuthFailure.invalidCredentials());
      await buildRepository().signIn(email: 'a@b.c', password: 'wrong');
      expect((await sessionStore.read()).valueOrNull, isNull);
    });

    test('succeeds even if the local cache cannot be written', () async {
      // The user can work; the session simply will not survive a restart.
      final AuthRepositoryImpl repository = AuthRepositoryImpl(
        authService: authService,
        sessionStore: _FailingSessionStore(),
        connectivity: connectivity,
        deviceInfo: const StaticDeviceInfoService(),
        auditSink: auditSink,
        idGenerator: SequentialIdGenerator(),
        clock: clock,
        logger: AppLogger(
          minimumLevel: LogLevel.debug,
          sinks: <LogSink>[logSink],
        ),
        config: config,
      );

      final Result<AuthSession> result = await repository.signIn(
        email: 'teacher@natco.test',
        password: 'correct',
      );

      expect(result.isSuccess, isTrue);
      expect(
        logSink.records.map((LogRecord r) => r.event),
        contains('session_cache_write_failed'),
      );
    });
  });

  group('signOut', () {
    test('clears the local session and audits the event', () async {
      await buildRepository().signIn(
        email: 'teacher@natco.test',
        password: 'correct',
      );
      auditSink.clear();

      await buildRepository().signOut();

      expect((await sessionStore.read()).valueOrNull, isNull);
      expect(auditSink.events.single.action, AuditAction.logout);
      expect(authService.signOutCalls, 1);
    });

    test('clears local state even if the backend call fails', () async {
      // A sign-out that leaves a usable session behind because the network was
      // down would be a security defect.
      await seedCachedSession();
      final AuthRepositoryImpl repository = buildRepository();

      final Result<void> result = await repository.signOut();

      expect(result.isSuccess, isTrue);
      expect((await sessionStore.read()).valueOrNull, isNull);
    });
  });

  group('revalidate', () {
    setUp(() => connectivity.emit(ConnectionStatus.onlineUnmetered));

    test('does nothing when there is no cached session', () async {
      final Result<AuthSession?> result = await buildRepository().revalidate();
      expect(result.valueOrNull, isNull);
      expect(authService.refreshUserCalls, 0);
    });

    test('refreshes credentials so new claims apply immediately', () async {
      await seedCachedSession();
      authService.signedIn = _teacher();
      await buildRepository().revalidate();
      expect(authService.refreshCredentialsCalls, 1);
    });

    test('applies an updated role', () async {
      await seedCachedSession();
      authService.refreshUserResult = ok(_teacher(role: UserRole.supervisor));

      final Result<AuthSession?> result = await buildRepository().revalidate();

      expect(result.valueOrNull!.user.role, UserRole.supervisor);
    });

    test('clears the session when the account was deactivated', () async {
      await seedCachedSession();
      authService.refreshUserResult = err<AppUser>(
        AuthFailure.accountDisabled(),
      );

      final Result<AuthSession?> result = await buildRepository().revalidate();

      expect(result.isFailure, isTrue);
      expect((await sessionStore.read()).valueOrNull, isNull);
    });

    test('clears the session when the account no longer exists', () async {
      await seedCachedSession();
      authService.refreshUserResult = err<AppUser>(
        const NotFoundFailure(
          userMessage: 'That account could not be found.',
          entityType: 'user',
          entityId: 'u1',
        ),
      );

      expect((await buildRepository().revalidate()).isFailure, isTrue);
      expect((await sessionStore.read()).valueOrNull, isNull);
    });

    test('keeps the session on a transient failure', () async {
      await seedCachedSession();
      authService.refreshUserResult = err<AppUser>(NetworkFailure.timeout());

      final Result<AuthSession?> result = await buildRepository().revalidate();

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNotNull);
      expect((await sessionStore.read()).valueOrNull, isNotNull);
    });
  });

  group('requestPasswordReset', () {
    test('delegates to the backend', () async {
      expect(
        (await buildRepository().requestPasswordReset('a@b.c')).isSuccess,
        isTrue,
      );
    });

    test('propagates a genuine failure', () async {
      authService.passwordResetResult = err<void>(NetworkFailure.offline());
      expect(
        (await buildRepository().requestPasswordReset('a@b.c')).isFailure,
        isTrue,
      );
    });
  });
}

/// A store whose writes always fail, to exercise the degraded path.
final class _FailingSessionStore implements SessionStore {
  @override
  Future<Result<AuthSession?>> read() async => ok<AuthSession?>(null);

  @override
  Future<Result<void>> write(AuthSession session) async =>
      err<void>(StorageFailure.localWrite(diagnostic: 'disk full'));

  @override
  Future<Result<void>> clear() async => ok(null);
}
