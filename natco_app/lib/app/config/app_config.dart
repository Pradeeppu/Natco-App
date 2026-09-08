/// The resolved runtime configuration.
///
/// Built once at startup from the compile-time environment and, once a user is
/// signed in, refreshed from `app_config/global`. Nothing reads
/// `String.fromEnvironment` outside this file.
library;

import 'package:natco_app/app/config/app_environment.dart';
import 'package:natco_app/app/config/feature_flags.dart';
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/core/services/logger.dart';

/// Controlled vocabularies for dropdowns.
///
/// Teachers are never allowed to free-type a state, district, cluster or
/// school (requirement section 10); grade, section, subject, medium and
/// language are similarly constrained so that analytics can group them.
/// Shipped defaults are replaced by the server's list when available.
final class ControlledVocabularies {
  const ControlledVocabularies({
    this.grades = const <String>['1', '2', '3', '4', '5', '6', '7', '8'],
    this.sections = const <String>['A', 'B', 'C', 'D', 'E'],
    this.subjects = const <String>[
      'Mathematics',
      'Science',
      'English',
      'Social Studies',
      'Language',
    ],
    this.mediumsOfInstruction = const <String>['English', 'Hindi', 'Regional'],
    this.languages = const <String>['English', 'Hindi', 'Regional'],
    this.academicYears = const <String>['2025-26', '2026-27'],
  });

  final List<String> grades;
  final List<String> sections;
  final List<String> subjects;
  final List<String> mediumsOfInstruction;
  final List<String> languages;
  final List<String> academicYears;

  ControlledVocabularies copyWith({
    List<String>? grades,
    List<String>? sections,
    List<String>? subjects,
    List<String>? mediumsOfInstruction,
    List<String>? languages,
    List<String>? academicYears,
  }) => ControlledVocabularies(
    grades: grades ?? this.grades,
    sections: sections ?? this.sections,
    subjects: subjects ?? this.subjects,
    mediumsOfInstruction: mediumsOfInstruction ?? this.mediumsOfInstruction,
    languages: languages ?? this.languages,
    academicYears: academicYears ?? this.academicYears,
  );
}

final class AppConfig {
  const AppConfig({
    required this.environment,
    required this.logLevel,
    required this.featureFlags,
    required this.scannerThresholds,
    required this.vocabularies,
    required this.offlineSessionValidity,
    required this.syncMaxAutomaticAttempts,
    required this.listPageSize,
    required this.maxOmrImageBytes,
    required this.omrTemplateVersion,
  });

  /// Resolves configuration for [environment], applying that environment's
  /// defaults.
  factory AppConfig.forEnvironment(AppEnvironment environment) {
    return switch (environment) {
      AppEnvironment.dev => AppConfig(
        environment: environment,
        logLevel: LogLevel.debug,
        featureFlags: const FeatureFlags(
          enableDemoSeedData: true,
          uploadImagesOnMeteredConnection: true,
        ),
        scannerThresholds: const ScannerThresholds(),
        vocabularies: const ControlledVocabularies(),
        offlineSessionValidity: const Duration(days: 7),
        syncMaxAutomaticAttempts: 8,
        listPageSize: 25,
        maxOmrImageBytes: 8 * 1024 * 1024,
        omrTemplateVersion: 'natco_v1',
      ),
      AppEnvironment.staging => AppConfig(
        environment: environment,
        logLevel: LogLevel.info,
        featureFlags: const FeatureFlags(),
        scannerThresholds: const ScannerThresholds(),
        vocabularies: const ControlledVocabularies(),
        offlineSessionValidity: const Duration(days: 7),
        syncMaxAutomaticAttempts: 8,
        listPageSize: 25,
        maxOmrImageBytes: 8 * 1024 * 1024,
        omrTemplateVersion: 'natco_v1',
      ),
      AppEnvironment.prod => AppConfig(
        environment: environment,
        // Warnings and errors only: debug logging in production is both a
        // performance cost and a privacy risk.
        logLevel: LogLevel.warning,
        featureFlags: const FeatureFlags(),
        scannerThresholds: const ScannerThresholds(),
        vocabularies: const ControlledVocabularies(),
        offlineSessionValidity: const Duration(days: 7),
        syncMaxAutomaticAttempts: 8,
        listPageSize: 25,
        maxOmrImageBytes: 8 * 1024 * 1024,
        omrTemplateVersion: 'natco_v1',
      ),
      AppEnvironment.demo => AppConfig(
        environment: environment,
        logLevel: LogLevel.debug,
        featureFlags: const FeatureFlags(
          enableDemoSeedData: true,
          enableCrashReporting: false,
          uploadImagesOnMeteredConnection: true,
          enforceMinimumAppVersion: false,
        ),
        scannerThresholds: const ScannerThresholds(),
        vocabularies: const ControlledVocabularies(),
        offlineSessionValidity: const Duration(days: 365),
        syncMaxAutomaticAttempts: 3,
        listPageSize: 25,
        maxOmrImageBytes: 8 * 1024 * 1024,
        omrTemplateVersion: 'natco_v1',
      ),
    };
  }

  /// Reads `--dart-define=NATCO_ENV=<name>`.
  factory AppConfig.fromEnvironment() => AppConfig.forEnvironment(
    AppEnvironment.fromName(
      const String.fromEnvironment('NATCO_ENV', defaultValue: 'demo'),
    ),
  );

  final AppEnvironment environment;
  final LogLevel logLevel;
  final FeatureFlags featureFlags;
  final ScannerThresholds scannerThresholds;
  final ControlledVocabularies vocabularies;

  /// How long a cached session permits offline use before a connected sign-in
  /// is required again (docs/04-security-model.md).
  final Duration offlineSessionValidity;

  /// After this many failed attempts an entry stops auto-retrying and is
  /// surfaced to a human. It is never discarded.
  final int syncMaxAutomaticAttempts;

  final int listPageSize;
  final int maxOmrImageBytes;

  /// Which OMR sheet geometry this build reads. Recorded on every submission.
  final String omrTemplateVersion;

  AppConfig copyWith({
    LogLevel? logLevel,
    FeatureFlags? featureFlags,
    ScannerThresholds? scannerThresholds,
    ControlledVocabularies? vocabularies,
    Duration? offlineSessionValidity,
    int? syncMaxAutomaticAttempts,
    int? listPageSize,
    int? maxOmrImageBytes,
    String? omrTemplateVersion,
  }) => AppConfig(
    environment: environment,
    logLevel: logLevel ?? this.logLevel,
    featureFlags: featureFlags ?? this.featureFlags,
    scannerThresholds: scannerThresholds ?? this.scannerThresholds,
    vocabularies: vocabularies ?? this.vocabularies,
    offlineSessionValidity:
        offlineSessionValidity ?? this.offlineSessionValidity,
    syncMaxAutomaticAttempts:
        syncMaxAutomaticAttempts ?? this.syncMaxAutomaticAttempts,
    listPageSize: listPageSize ?? this.listPageSize,
    maxOmrImageBytes: maxOmrImageBytes ?? this.maxOmrImageBytes,
    omrTemplateVersion: omrTemplateVersion ?? this.omrTemplateVersion,
  );
}
