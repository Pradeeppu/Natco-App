/// The composition root.
///
/// Every service and repository in the app is constructed here, behind a
/// Riverpod provider. Swapping the backend means changing this file and
/// nothing else (docs/01-architecture.md); running the app with no backend at
/// all means selecting `AppEnvironment.demo`, which is also how the widget
/// tests run.
///
/// Nothing outside this file calls a Firebase constructor or reads
/// `String.fromEnvironment`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/core/services/crash_reporter.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/auth/data/repository/auth_repository_impl.dart';
import 'package:natco_app/features/auth/data/service/auth_service.dart';
import 'package:natco_app/features/auth/data/service/firebase_auth_service.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/data/store/session_store.dart';
import 'package:natco_app/features/auth/domain/repository/auth_repository.dart';
import 'package:natco_app/features/auth/presentation/controller/session_controller.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

/// The resolved configuration.
///
/// Overridden in tests and in `main` after startup has read the environment,
/// so that no provider reads compile-time constants on its own.
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>(
  (Ref ref) => AppConfig.fromEnvironment(),
);

/// In-memory log sink, kept so the diagnostics screen can show and export
/// recent records without a cable.
final Provider<InMemoryLogSink> logBufferProvider = Provider<InMemoryLogSink>(
  (Ref ref) => InMemoryLogSink(),
);

final Provider<AppLogger> loggerProvider = Provider<AppLogger>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return AppLogger(
    minimumLevel: config.logLevel,
    sinks: <LogSink>[const DeveloperLogSink(), ref.watch(logBufferProvider)],
  );
});

final Provider<Clock> clockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

final Provider<IdGenerator> idGeneratorProvider = Provider<IdGenerator>(
  (Ref ref) => const UuidIdGenerator(),
);

/// Device identity and app version. Overridden in `main` with the values read
/// from the platform, and in tests with fixed values.
final Provider<DeviceInfoService> deviceInfoProvider =
    Provider<DeviceInfoService>((Ref ref) => const StaticDeviceInfoService());

final Provider<CrashReporter> crashReporterProvider = Provider<CrashReporter>(
  (Ref ref) => const NoopCrashReporter(),
);

/// Audit destination.
///
/// Phase 1 collects entries in memory; phase 9 replaces this with a
/// queue-backed sink that survives restarts and uploads through the sync
/// engine (docs/08-mvp-implementation-plan.md).
final Provider<AuditSink> auditSinkProvider = Provider<AuditSink>(
  (Ref ref) => InMemoryAuditSink(),
);

final Provider<ConnectivityService> connectivityProvider =
    Provider<ConnectivityService>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        // Demo mode reports a working connection so the whole signed-in
        // experience is reachable without a network.
        return FakeConnectivityService();
      }
      final PlatformConnectivityService service = PlatformConnectivityService();
      ref.onDispose(service.dispose);
      return service;
    });

/// Hive, for the encrypted session box.
final Provider<HiveInterface> hiveProvider = Provider<HiveInterface>(
  (Ref ref) => Hive,
);

final Provider<FlutterSecureStorage> secureStorageProvider =
    Provider<FlutterSecureStorage>(
      (Ref ref) => const FlutterSecureStorage(
        // `resetOnError` is left at its default: if the keystore entry cannot
        // be read, discarding it costs the user one sign-in, whereas throwing
        // on every launch would make the app unusable with no way out.
        aOptions: AndroidOptions(storageNamespace: 'natco_secure_v1'),
      ),
    );

/// The demo accounts, exposed so the login screen can offer them as hints in
/// demo mode. Empty in every environment that uses a real backend.
final Provider<List<DemoAccount>> demoAccountsProvider =
    Provider<List<DemoAccount>>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      return config.environment.usesFirebase
          ? const <DemoAccount>[]
          : buildDemoAccounts();
    });

final Provider<AuthService> authServiceProvider = Provider<AuthService>((
  Ref ref,
) {
  final AppConfig config = ref.watch(appConfigProvider);
  if (!config.environment.usesFirebase) {
    final InMemoryAuthService service = InMemoryAuthService(
      accounts: ref.watch(demoAccountsProvider),
      clock: ref.watch(clockProvider),
      latency: const Duration(milliseconds: 250),
    );
    ref.onDispose(service.dispose);
    return service;
  }
  return FirebaseAuthService(
    auth: fb.FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    logger: ref.watch(loggerProvider),
  );
});

final Provider<SessionStore> sessionStoreProvider = Provider<SessionStore>((
  Ref ref,
) {
  final AppConfig config = ref.watch(appConfigProvider);
  if (!config.environment.usesFirebase) {
    return InMemorySessionStore();
  }
  return SecureSessionStore(
    hive: ref.watch(hiveProvider),
    secureStorage: ref.watch(secureStorageProvider),
    logger: ref.watch(loggerProvider),
  );
});

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => AuthRepositoryImpl(
        authService: ref.watch(authServiceProvider),
        sessionStore: ref.watch(sessionStoreProvider),
        connectivity: ref.watch(connectivityProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        logger: ref.watch(loggerProvider),
        config: ref.watch(appConfigProvider),
      ),
    );

/// The session, owned for the lifetime of the app.
final NotifierProvider<SessionController, SessionState> sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Emits the current connection status for the offline banner.
///
/// The current status is yielded before subscribing to changes. Without that
/// seed the first value would only arrive on the first *transition*, so a
/// device that starts offline and stays offline would never show the offline
/// banner — the state the banner exists for.
final StreamProvider<ConnectionStatus> connectionStatusProvider =
    StreamProvider<ConnectionStatus>((Ref ref) async* {
      final ConnectivityService service = ref.watch(connectivityProvider);
      yield await service.current();
      yield* service.changes();
    });
