/// Application entry point.
///
/// Startup order matters and is explicit:
///
/// 1. read the compile-time environment,
/// 2. initialise local storage (needed before any session restore),
/// 3. initialise the backend only when the environment uses one,
/// 4. install crash handlers before the first frame,
/// 5. run the app with the resolved configuration injected.
///
/// A failure at step 3 does not stop the app: a phone that cannot reach
/// Firebase at launch must still open, show its cached session and let a
/// teacher work (requirement section 23). It is logged and reported instead.
library;

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/app.dart';
import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/services/crash_reporter.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/data/local/hive_bootstrap.dart';
import 'package:natco_app/data/local/platform_device_info_service.dart';
import 'package:natco_app/data/remote/firebase_crash_reporter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppConfig config = AppConfig.fromEnvironment();
  final InMemoryLogSink logBuffer = InMemoryLogSink();
  final AppLogger logger = AppLogger(
    minimumLevel: config.logLevel,
    sinks: <LogSink>[const DeveloperLogSink(), logBuffer],
  );

  await initialiseLocalStorage(logger: logger);

  final DeviceInfoService deviceInfo = await PlatformDeviceInfoService.load(
    deviceInfoPlugin: DeviceInfoPlugin(),
    logger: logger,
  );

  CrashReporter crashReporter = const NoopCrashReporter();
  if (config.environment.usesFirebase) {
    crashReporter = await _initialiseBackend(
      config: config,
      logger: logger,
      deviceInfo: deviceInfo,
    );
  }

  _installErrorHandlers(logger: logger, crashReporter: crashReporter);

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        logBufferProvider.overrideWithValue(logBuffer),
        loggerProvider.overrideWithValue(logger),
        deviceInfoProvider.overrideWithValue(deviceInfo),
        crashReporterProvider.overrideWithValue(crashReporter),
      ],
      child: const NatcoApp(),
    ),
  );
}

/// Brings up Firebase. Returns a working crash reporter, or the no-op one if
/// initialisation failed — the app continues either way.
Future<CrashReporter> _initialiseBackend({
  required AppConfig config,
  required AppLogger logger,
  required DeviceInfoService deviceInfo,
}) async {
  try {
    await Firebase.initializeApp();
  } catch (error, stackTrace) {
    logger.error(
      'firebase_init_failed',
      fields: <String, Object?>{'env': config.environment.name},
      error: error,
      stackTrace: stackTrace,
    );
    return const NoopCrashReporter();
  }
  if (!config.featureFlags.enableCrashReporting) {
    return const NoopCrashReporter();
  }
  final FirebaseCrashReporter reporter = FirebaseCrashReporter(
    crashlytics: FirebaseCrashlytics.instance,
  );
  await reporter.setCustomKey('env', config.environment.name);
  await reporter.setCustomKey('device', deviceInfo.platformDescription);
  await reporter.setCustomKey('omr_template', config.omrTemplateVersion);
  return reporter;
}

/// Routes every uncaught error to the logger and the crash reporter.
///
/// Without this, a framework error prints a red screen and vanishes; with it,
/// the same error is recorded with enough context to act on.
void _installErrorHandlers({
  required AppLogger logger,
  required CrashReporter crashReporter,
}) {
  final FlutterExceptionHandler? previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'flutter_error',
      fields: <String, Object?>{
        'library': details.library,
        'context': details.context?.toDescription(),
      },
      error: details.exception,
      stackTrace: details.stack,
    );
    unawaited(
      crashReporter.recordError(
        details.exception,
        details.stack,
        reason: details.library,
        fatal: true,
      ),
    );
    previousOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    logger.error('uncaught_async_error', error: error, stackTrace: stackTrace);
    unawaited(crashReporter.recordError(error, stackTrace, fatal: true));
    // Returning true marks the error handled: the app stays up, and the
    // record is already preserved.
    return true;
  };
}
