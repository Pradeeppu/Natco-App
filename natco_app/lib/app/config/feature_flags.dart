/// Feature flags.
///
/// Defaults are per-environment; overrides arrive from `app_config/global` so
/// a misbehaving feature can be turned off in the field without shipping a
/// release (requirement section 54).
library;

/// Which implementation reads the pixels.
enum OmrProcessorKind {
  /// Pure Dart. Slower, but testable on CI with no device, which is what makes
  /// measured accuracy achievable (docs/07-omr-pipeline.md, section 5).
  dart,

  /// Native OpenCV behind a platform channel. Faster; verified against the
  /// same golden outputs as the Dart implementation.
  native,
}

final class FeatureFlags {
  const FeatureFlags({
    this.omrProcessor = OmrProcessorKind.dart,
    this.allowGalleryImport = true,
    this.allowOfflineLogin = true,
    this.uploadImagesOnMeteredConnection = false,
    this.enableCrashReporting = true,
    this.enableDemoSeedData = false,
    this.showDiagnosticsScreen = true,
    this.enforceMinimumAppVersion = true,
  });

  final OmrProcessorKind omrProcessor;

  /// Requirement section 16 asks for gallery import; the flag exists so a
  /// deployment that wants camera-only capture (tighter provenance) can have
  /// it without a code change.
  final bool allowGalleryImport;

  final bool allowOfflineLogin;

  /// Off by default: a teacher on prepaid data should not lose their balance
  /// to a batch of photographs.
  final bool uploadImagesOnMeteredConnection;

  final bool enableCrashReporting;
  final bool enableDemoSeedData;
  final bool showDiagnosticsScreen;
  final bool enforceMinimumAppVersion;

  FeatureFlags copyWith({
    OmrProcessorKind? omrProcessor,
    bool? allowGalleryImport,
    bool? allowOfflineLogin,
    bool? uploadImagesOnMeteredConnection,
    bool? enableCrashReporting,
    bool? enableDemoSeedData,
    bool? showDiagnosticsScreen,
    bool? enforceMinimumAppVersion,
  }) => FeatureFlags(
    omrProcessor: omrProcessor ?? this.omrProcessor,
    allowGalleryImport: allowGalleryImport ?? this.allowGalleryImport,
    allowOfflineLogin: allowOfflineLogin ?? this.allowOfflineLogin,
    uploadImagesOnMeteredConnection:
        uploadImagesOnMeteredConnection ?? this.uploadImagesOnMeteredConnection,
    enableCrashReporting: enableCrashReporting ?? this.enableCrashReporting,
    enableDemoSeedData: enableDemoSeedData ?? this.enableDemoSeedData,
    showDiagnosticsScreen: showDiagnosticsScreen ?? this.showDiagnosticsScreen,
    enforceMinimumAppVersion:
        enforceMinimumAppVersion ?? this.enforceMinimumAppVersion,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'omrProcessor': omrProcessor.name,
    'allowGalleryImport': allowGalleryImport,
    'allowOfflineLogin': allowOfflineLogin,
    'uploadImagesOnMeteredConnection': uploadImagesOnMeteredConnection,
    'enableCrashReporting': enableCrashReporting,
    'enableDemoSeedData': enableDemoSeedData,
    'showDiagnosticsScreen': showDiagnosticsScreen,
    'enforceMinimumAppVersion': enforceMinimumAppVersion,
  };

  /// Applies server overrides on top of this set. Unknown keys are ignored so
  /// an older build tolerates a newer config document.
  FeatureFlags withOverrides(Map<String, Object?> overrides) {
    bool? flag(String key) {
      final Object? value = overrides[key];
      return value is bool ? value : null;
    }

    return copyWith(
      omrProcessor: switch (overrides['omrProcessor']) {
        'dart' => OmrProcessorKind.dart,
        'native' => OmrProcessorKind.native,
        _ => null,
      },
      allowGalleryImport: flag('allowGalleryImport'),
      allowOfflineLogin: flag('allowOfflineLogin'),
      uploadImagesOnMeteredConnection: flag('uploadImagesOnMeteredConnection'),
      enableCrashReporting: flag('enableCrashReporting'),
      enableDemoSeedData: flag('enableDemoSeedData'),
      showDiagnosticsScreen: flag('showDiagnosticsScreen'),
      enforceMinimumAppVersion: flag('enforceMinimumAppVersion'),
    );
  }
}
