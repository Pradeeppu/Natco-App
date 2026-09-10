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
import 'package:natco_app/core/services/file_system_service.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/analytics/data/repository/firestore_analytics_repository_impl.dart';
import 'package:natco_app/features/analytics/data/repository/live_analytics_repository_impl.dart';
import 'package:natco_app/features/analytics/domain/repository/analytics_repository.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/session_repository_impl.dart';
import 'package:natco_app/features/assessment_sessions/data/service/demo_session_data.dart';
import 'package:natco_app/features/assessment_sessions/data/service/session_store.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_repository.dart';
import 'package:natco_app/features/assessments/data/repository/assessment_repository_impl.dart';
import 'package:natco_app/features/assessments/data/service/assessment_data_source.dart';
import 'package:natco_app/features/assessments/data/service/demo_assessment_data.dart';
import 'package:natco_app/features/assessments/data/service/firestore_assessment_data_source.dart';
import 'package:natco_app/features/assessments/data/service/in_memory_assessment_data_source.dart';
import 'package:natco_app/features/assessments/domain/repository/assessment_repository.dart';
import 'package:natco_app/features/auth/data/repository/auth_repository_impl.dart';
import 'package:natco_app/features/auth/data/service/auth_service.dart';
import 'package:natco_app/features/auth/data/service/firebase_auth_service.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/data/store/session_store.dart';
import 'package:natco_app/features/auth/domain/repository/auth_repository.dart';
import 'package:natco_app/features/auth/presentation/controller/session_controller.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/omr_validation/data/repository/omr_validation_repository_impl.dart';
import 'package:natco_app/features/omr_validation/data/service/demo_omr_data.dart';
import 'package:natco_app/features/omr_validation/data/service/firestore_omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/data/service/in_memory_omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/data/service/omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/reports/data/repository/report_repository_impl.dart';
import 'package:natco_app/features/reports/domain/repository/report_repository.dart';
import 'package:natco_app/features/results/data/repository/result_repository_impl.dart';
import 'package:natco_app/features/results/data/service/firestore_result_data_source.dart';
import 'package:natco_app/features/results/data/service/in_memory_result_data_source.dart';
import 'package:natco_app/features/results/data/service/result_data_source.dart';
import 'package:natco_app/features/results/domain/repository/result_repository.dart';
import 'package:natco_app/features/schools/data/repository/school_hierarchy_repository_impl.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';
import 'package:natco_app/features/schools/data/service/firestore_school_data_source.dart';
import 'package:natco_app/features/schools/data/service/in_memory_school_data_source.dart';
import 'package:natco_app/features/schools/data/service/school_data_source.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/students/data/repository/student_repository_impl.dart';
import 'package:natco_app/features/students/data/service/firestore_student_data_source.dart';
import 'package:natco_app/features/students/data/service/in_memory_student_data_source.dart';
import 'package:natco_app/features/students/data/service/student_data_source.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';
import 'package:natco_app/features/sync/data/repository/sync_queue_repository_impl.dart';
import 'package:natco_app/features/sync/data/service/hive_sync_queue_data_source.dart';
import 'package:natco_app/features/sync/data/service/in_memory_sync_backend_service.dart';
import 'package:natco_app/features/sync/data/service/sync_queue_data_source.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';
import 'package:natco_app/features/sync/domain/service/sync_conflict_policy.dart';
import 'package:natco_app/features/sync/domain/service/sync_engine.dart';
import 'package:natco_app/features/sync/domain/service/sync_reconciler.dart';
import 'package:natco_app/features/users/data/repository/user_repository_impl.dart';
import 'package:natco_app/features/users/data/service/firestore_user_data_source.dart';
import 'package:natco_app/features/users/data/service/in_memory_user_data_source.dart';
import 'package:natco_app/features/users/data/service/user_data_source.dart';
import 'package:natco_app/features/users/domain/repository/user_repository.dart';

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

// -------------------------------------------------------------- master data

final Provider<SchoolDataSource> schoolDataSourceProvider =
    Provider<SchoolDataSource>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemorySchoolDataSource(
          states: demoStates(),
          districts: demoDistricts(),
          clusters: demoClusters(),
          schools: demoSchools(),
        );
      }
      return FirestoreSchoolDataSource(FirebaseFirestore.instance);
    });

final Provider<SchoolHierarchyRepository> schoolHierarchyRepositoryProvider =
    Provider<SchoolHierarchyRepository>(
      (Ref ref) => SchoolHierarchyRepositoryImpl(
        dataSource: ref.watch(schoolDataSourceProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      ),
    );

final Provider<StudentDataSource> studentDataSourceProvider =
    Provider<StudentDataSource>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemoryStudentDataSource(students: demoStudents());
      }
      return FirestoreStudentDataSource(FirebaseFirestore.instance);
    });

final Provider<StudentRepository> studentRepositoryProvider =
    Provider<StudentRepository>(
      (Ref ref) => StudentRepositoryImpl(
        dataSource: ref.watch(studentDataSourceProvider),
        schoolRepository: ref.watch(schoolHierarchyRepositoryProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      ),
    );

// --------------------------------------------------------------- assessments

final Provider<AssessmentDataSource> assessmentDataSourceProvider =
    Provider<AssessmentDataSource>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemoryAssessmentDataSource(
          assessments: demoAssessments(),
          answerKeys: demoAnswerKeys(),
          assignments: demoAssignments(),
        );
      }
      return FirestoreAssessmentDataSource(FirebaseFirestore.instance);
    });

final Provider<AssessmentRepository> assessmentRepositoryProvider =
    Provider<AssessmentRepository>(
      (Ref ref) => AssessmentRepositoryImpl(
        dataSource: ref.watch(assessmentDataSourceProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      ),
    );

// ------------------------------------------------------------------ sessions

/// Local-first: Hive on a device, in-memory in demo mode and tests. Both
/// halves of the app talk to sessions through this store regardless of which
/// backend is configured — see `SessionStore`'s doc for why.
final Provider<AssessmentSessionStore> assessmentSessionStoreProvider =
    Provider<AssessmentSessionStore>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemoryAssessmentSessionStore(sessions: demoSessions());
      }
      // Phase 9 replaces this with `HiveAssessmentSessionStore.open(...)`
      // resolved at startup once the box is available; for now
      // `prod`/`dev`/`staging` share the same in-memory behaviour rather
      // than a half-wired Hive path with no sync engine to drain it.
      return InMemoryAssessmentSessionStore();
    });

final Provider<SessionRepository> sessionRepositoryProvider =
    Provider<SessionRepository>(
      (Ref ref) => SessionRepositoryImpl(
        store: ref.watch(assessmentSessionStoreProvider),
        assessmentRepository: ref.watch(assessmentRepositoryProvider),
        schoolRepository: ref.watch(schoolHierarchyRepositoryProvider),
        studentRepository: ref.watch(studentRepositoryProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      ),
    );

// --------------------------------------------------------------------- users

final Provider<UserDataSource> userDataSourceProvider = Provider<UserDataSource>(
  (Ref ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    if (!config.environment.usesFirebase) {
      // Seeded from the same demo accounts the login screen offers, so the
      // Users screen and the sign-in chips cannot describe different people.
      return InMemoryUserDataSource(
        users: ref
            .watch(demoAccountsProvider)
            .map((DemoAccount account) => account.user)
            .toList(growable: false),
      );
    }
    return FirestoreUserDataSource(FirebaseFirestore.instance);
  },
);

final Provider<UserRepository> userRepositoryProvider = Provider<UserRepository>(
  (Ref ref) => UserRepositoryImpl(
    dataSource: ref.watch(userDataSourceProvider),
    schoolRepository: ref.watch(schoolHierarchyRepositoryProvider),
    auditSink: ref.watch(auditSinkProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
    deviceInfo: ref.watch(deviceInfoProvider),
  ),
);

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

// ---------------------------------------------------------------------- sync

final Provider<FileSystemService> fileSystemServiceProvider =
    Provider<FileSystemService>((Ref ref) {
      // Demo and real currently use PlatformFileSystemService.
      // Tests will override this with FakeFileSystemService.
      return const PlatformFileSystemService();
    });

final Provider<SyncQueueDataSource> syncQueueDataSourceProvider =
    Provider<SyncQueueDataSource>((Ref ref) {
      // Requires Hive box 'sync_queue' to be opened during init.
      return HiveSyncQueueDataSource(ref.watch(hiveProvider).box<dynamic>('sync_queue'));
    });

final Provider<SyncBackendService> syncBackendServiceProvider =
    Provider<SyncBackendService>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemorySyncBackendService();
      }
      // Placeholder for actual Firestore sync backend
      return InMemorySyncBackendService(); 
    });

final Provider<SyncConflictPolicy> syncConflictPolicyProvider =
    Provider<SyncConflictPolicy>((Ref ref) => const SyncConflictPolicy());

final Provider<SyncQueueRepository> syncQueueRepositoryProvider =
    Provider<SyncQueueRepository>((Ref ref) {
      return SyncQueueRepositoryImpl(
        dataSource: ref.watch(syncQueueDataSourceProvider),
        conflictPolicy: ref.watch(syncConflictPolicyProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      );
    });

final Provider<SyncEngine> syncEngineProvider = Provider<SyncEngine>((Ref ref) {
  return SyncEngine(
    queueRepository: ref.watch(syncQueueRepositoryProvider),
    backend: ref.watch(syncBackendServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

final Provider<SyncReconciler> syncReconcilerProvider =
    Provider<SyncReconciler>((Ref ref) {
      return SyncReconciler(
        queueRepository: ref.watch(syncQueueRepositoryProvider),
        omrRepository: ref.watch(omrValidationRepositoryProvider),
        fileSystem: ref.watch(fileSystemServiceProvider),
      );
    });

// ------------------------------------------------------------ omr validation

final Provider<OmrValidationDataSource> omrValidationDataSourceProvider =
    Provider<OmrValidationDataSource>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemoryOmrValidationDataSource(
          submissions: demoOmrSubmissions(),
          answers: demoOmrAnswers(),
        );
      }
      return FirestoreOmrValidationDataSource(FirebaseFirestore.instance);
    });

final Provider<OmrValidationRepository> omrValidationRepositoryProvider =
    Provider<OmrValidationRepository>(
      (Ref ref) => OmrValidationRepositoryImpl(
        dataSource: ref.watch(omrValidationDataSourceProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      ),
    );

// ------------------------------------------------------------------ results

final Provider<ResultDataSource> resultDataSourceProvider =
    Provider<ResultDataSource>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return InMemoryResultDataSource();
      }
      return FirestoreResultDataSource(FirebaseFirestore.instance);
    });

final Provider<ResultRepository> resultRepositoryProvider =
    Provider<ResultRepository>(
      (Ref ref) => ResultRepositoryImpl(
        dataSource: ref.watch(resultDataSourceProvider),
        omrRepository: ref.watch(omrValidationRepositoryProvider),
        sessionRepository: ref.watch(sessionRepositoryProvider),
        assessmentRepository: ref.watch(assessmentRepositoryProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      ),
    );

// ---------------------------------------------------------------- analytics

final Provider<AnalyticsRepository> analyticsRepositoryProvider =
    Provider<AnalyticsRepository>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      if (!config.environment.usesFirebase) {
        return LiveAnalyticsRepositoryImpl(
          resultRepository: ref.watch(resultRepositoryProvider),
          omrRepository: ref.watch(omrValidationRepositoryProvider),
          sessionRepository: ref.watch(sessionRepositoryProvider),
        );
      }
      return FirestoreAnalyticsRepositoryImpl(FirebaseFirestore.instance);
    });

// ------------------------------------------------------------------ reports

// No environment branch: `ReportRepositoryImpl` only composes other
// already-environment-aware repositories (results, analytics, OMR, sync,
// schools, students) — it has no backend touchpoint of its own to swap.
final Provider<ReportRepository> reportRepositoryProvider =
    Provider<ReportRepository>(
      (Ref ref) => ReportRepositoryImpl(
        resultRepository: ref.watch(resultRepositoryProvider),
        analyticsRepository: ref.watch(analyticsRepositoryProvider),
        omrRepository: ref.watch(omrValidationRepositoryProvider),
        syncQueueRepository: ref.watch(syncQueueRepositoryProvider),
        schoolRepository: ref.watch(schoolHierarchyRepositoryProvider),
        studentRepository: ref.watch(studentRepositoryProvider),
        assessmentRepository: ref.watch(assessmentRepositoryProvider),
        auditSink: ref.watch(auditSinkProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
        deviceInfo: ref.watch(deviceInfoProvider),
      ),
    );
