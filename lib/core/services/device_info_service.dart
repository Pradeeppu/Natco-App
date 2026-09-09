/// Device identity and app version, for audit records and sync provenance.
///
/// `deviceId` is a required audit field (requirement section 26). It is an
/// installation-scoped random identifier persisted on the device, not a
/// hardware serial or advertising id: the audit trail needs to distinguish
/// devices, not to identify them, and a hardware identifier is personal data
/// we have no reason to hold.
library;

abstract interface class DeviceInfoService {
  /// Stable-per-installation opaque device identifier.
  String get deviceId;

  /// App version name, e.g. `0.1.0`.
  String get appVersion;

  /// Build number, e.g. `1`.
  String get buildNumber;

  /// Human-readable model description for diagnostics, e.g. `Android 11 /
  /// SM-A105F`. Used to slice OMR accuracy and performance by device class.
  String get platformDescription;
}

/// Fixed values, for tests and demo mode.
final class StaticDeviceInfoService implements DeviceInfoService {
  const StaticDeviceInfoService({
    this.deviceId = 'demo-device',
    this.appVersion = '0.0.0',
    this.buildNumber = '0',
    this.platformDescription = 'test-harness',
  });

  @override
  final String deviceId;

  @override
  final String appVersion;

  @override
  final String buildNumber;

  @override
  final String platformDescription;
}
