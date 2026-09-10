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
import 'package:natco_app/data/local/demo_assessment_data.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/hive_assessment_sessions_repository.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/hive_session_prerequisites_repository.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/in_memory_assessment_sessions_repository.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/in_memory_session_prerequisites_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/assessment_sessions_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_prerequisites_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/service/session_prerequisites_downloader.dart';
import 'package:natco_app/features/assessments/data/repository/firestore_assessments_repository.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/assessments/domain/repository/assessments_repository.dart';
import 'package:natco_app/features/auth/data/repository/auth_repository_impl.dart';
import 'package:natco_app/features/auth/data/service/auth_service.dart';
import 'package:natco_app/features/auth/data/service/firebase_auth_service.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/data/store/session_store.dart';
import 'package:natco_app/features/auth/domain/repository/auth_repository.dart';
import 'package:natco_app/features/auth/presentation/controller/session_controller.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/omr_capture/data/repository/hive_omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/data/repository/in_memory_omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/data/service/image_picker_service.dart';
import 'package:natco_app/features/omr_capture/data/service/omr_image_store.dart';
import 'package:natco_app/features/omr_capture/domain/repository/omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/domain/service/image_quality_analyzer.dart';
import 'package:natco_app/features/schools/data/repository/firestore_schools_repository.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/schools_repository.dart';
import 'package:natco_app/features/students/data/repository/firestore_students_repository.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';
import 'package:natco_app/features/students/domain/repository/students_repository.dart';
import 'package:path_provider/path_provider.dart';

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

/// Bundles the two in-memory master-data repositories so they can share one
/// underlying dataset.
///
/// [InMemoryStudentsRepository] needs [InMemorySchoolsRepository] to resolve
/// a new student's ancestry (docs/02-data-model.md), and the demo seed
/// data — one school hierarchy, students enrolled in it — only makes sense
/// as a single dataset. Two independent providers each constructing their
/// own repository would seed two unrelated worlds.
final class _InMemoryMasterData {
  const _InMemoryMasterData({
    required this.schools,
    required this.students,
    required this.assessments,
  });

  final InMemorySchoolsRepository schools;
  final InMemoryStudentsRepository students;
  final InMemoryAssessmentsRepository assessments;
}

final Provider<_InMemoryMasterData> _inMemoryMasterDataProvider =
    Provider<_InMemoryMasterData>((Ref ref) {
      final IdGenerator idGenerator = ref.watch(idGeneratorProvider);
      final Clock clock = ref.watch(clockProvider);
      final InMemorySchoolsRepository schools = InMemorySchoolsRepository(
        idGenerator: idGenerator,
        clock: clock,
      );
      final InMemoryStudentsRepository students = InMemoryStudentsRepository(
        idGenerator: idGenerator,
        clock: clock,
        schools: schools,
      );
      final InMemoryAssessmentsRepository assessments =
          InMemoryAssessmentsRepository(
            idGenerator: idGenerator,
            clock: clock,
            schools: schools,
          );
      if (ref.watch(appConfigProvider).featureFlags.enableDemoSeedData) {
        final List<School> seededSchools = seedDemoMasterData(
          schools: schools,
          students: students,
          idGenerator: idGenerator,
          clock: clock,
        );
        seedDemoAssessmentData(
          assessments: assessments,
          seededSchools: seededSchools,
          idGenerator: idGenerator,
          clock: clock,
        );
      }
      return _InMemoryMasterData(
        schools: schools,
        students: students,
        assessments: assessments,
      );
    });

final Provider<SchoolsRepository> schoolsRepositoryProvider =
    Provider<SchoolsRepository>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return ref.watch(_inMemoryMasterDataProvider).schools;
      }
      return FirestoreSchoolsRepository(firestore: FirebaseFirestore.instance);
    });

final Provider<StudentsRepository> studentsRepositoryProvider =
    Provider<StudentsRepository>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return ref.watch(_inMemoryMasterDataProvider).students;
      }
      return FirestoreStudentsRepository(
        firestore: FirebaseFirestore.instance,
        idGenerator: ref.watch(idGeneratorProvider),
      );
    });

final Provider<AssessmentsRepository> assessmentsRepositoryProvider =
    Provider<AssessmentsRepository>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return ref.watch(_inMemoryMasterDataProvider).assessments;
      }
      return FirestoreAssessmentsRepository(
        firestore: FirebaseFirestore.instance,
      );
    });

/// Local cache of session prerequisites: pure Hive storage in real
/// environments, an in-memory map in demo/tests — the same environment split
/// every other repository in this file uses, and consistent with it: demo
/// mode does not need to survive a real process restart, and using Hive
/// there would only add I/O to widget tests that already run the whole app
/// in memory.
final Provider<SessionPrerequisitesRepository>
sessionPrerequisitesRepositoryProvider = Provider<SessionPrerequisitesRepository>((
  Ref ref,
) {
  final AppConfig config = ref.watch(appConfigProvider);
  if (!config.environment.usesFirebase) {
    return InMemorySessionPrerequisitesRepository();
  }
  return HiveSessionPrerequisitesRepository(
    hive: ref.watch(hiveProvider),
    logger: ref.watch(loggerProvider),
  );
});

final Provider<SessionPrerequisitesDownloader>
sessionPrerequisitesDownloaderProvider = Provider<SessionPrerequisitesDownloader>((
  Ref ref,
) => SessionPrerequisitesDownloader(
  assessments: ref.watch(assessmentsRepositoryProvider),
  schools: ref.watch(schoolsRepositoryProvider),
  students: ref.watch(studentsRepositoryProvider),
  cache: ref.watch(sessionPrerequisitesRepositoryProvider),
  clock: ref.watch(clockProvider),
));

/// A teacher's assessment sessions. Always local-first (docs/06-offline-sync-
/// strategy.md §1): even the Firebase-backed environments use Hive here, not
/// Firestore, because a session has to be startable and runnable with no
/// network at all. Only demo/tests use the in-memory variant, which does not
/// need to survive a real process restart.
final Provider<AssessmentSessionsRepository> assessmentSessionsRepositoryProvider =
    Provider<AssessmentSessionsRepository>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemoryAssessmentSessionsRepository(
          idGenerator: ref.watch(idGeneratorProvider),
          clock: ref.watch(clockProvider),
        );
      }
      return HiveAssessmentSessionsRepository(
        hive: ref.watch(hiveProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        logger: ref.watch(loggerProvider),
      );
    });

/// Durable local storage for captured images. Not Firebase-dependent, so
/// every environment — including demo mode running on a real device — uses
/// the real filesystem store; only tests override this with one pointed at
/// a temp directory.
final Provider<OmrImageStore> omrImageStoreProvider = Provider<OmrImageStore>(
  (Ref ref) => FileSystemOmrImageStore(
    rootDirectory: getApplicationDocumentsDirectory,
  ),
);

/// Camera/gallery access. Not Firebase-dependent either, for the same reason
/// as [omrImageStoreProvider] — only tests override this, with a fake that
/// never touches a platform channel.
final Provider<ImagePickerService> imagePickerServiceProvider =
    Provider<ImagePickerService>((Ref ref) => PlatformImagePickerService());

/// Pure, stateless — constructed directly rather than behind an interface
/// swap, since there is nothing to replace it with yet (docs/07-omr-
/// pipeline.md §5: a native accelerator arrives behind this same call site
/// once the Dart pipeline is calibrated).
final Provider<ImageQualityAnalyzer> imageQualityAnalyzerProvider =
    Provider<ImageQualityAnalyzer>((Ref ref) => const ImageQualityAnalyzer());

/// Captured OMR submissions. Always local-first, the same reasoning as
/// [assessmentSessionsRepositoryProvider]: a capture has to succeed with no
/// network at all.
final Provider<OmrSubmissionsRepository> omrSubmissionsRepositoryProvider =
    Provider<OmrSubmissionsRepository>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemoryOmrSubmissionsRepository(clock: ref.watch(clockProvider));
      }
      return HiveOmrSubmissionsRepository(
        hive: ref.watch(hiveProvider),
        clock: ref.watch(clockProvider),
        logger: ref.watch(loggerProvider),
      );
    });

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
