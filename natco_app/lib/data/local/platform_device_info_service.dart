/// Device identity and app version, read from the platform.
///
/// `deviceId` is an installation-scoped random identifier persisted in Hive,
/// not a hardware serial: the audit trail needs to tell devices apart, not to
/// identify them, and a hardware id is personal data with no purpose here
/// (docs/04-security-model.md).
library;

import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

final class PlatformDeviceInfoService implements DeviceInfoService {
  const PlatformDeviceInfoService({
    required this.deviceId,
    required this.appVersion,
    required this.buildNumber,
    required this.platformDescription,
  });

  static const String _boxName = 'natco_device';
  static const String _deviceIdKey = 'deviceId';

  /// Reads everything the platform can tell us, falling back to safe defaults.
  ///
  /// Never throws: a missing package info or an unreadable box must not stop
  /// the app from starting.
  static Future<PlatformDeviceInfoService> load({
    required DeviceInfoPlugin deviceInfoPlugin,
    required AppLogger logger,
  }) async {
    String appVersion = 'unknown';
    String buildNumber = '0';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      buildNumber = info.buildNumber;
    } catch (error) {
      logger.warning('package_info_unavailable', error: error);
    }

    String platformDescription = 'unknown';
    try {
      final AndroidDeviceInfo android = await deviceInfoPlugin.androidInfo;
      platformDescription =
          'Android ${android.version.release} / ${android.model}';
    } catch (error) {
      // Non-Android hosts (including the test harness) land here. Not an
      // error worth raising, but worth recording once.
      logger.debug('device_info_unavailable');
    }

    return PlatformDeviceInfoService(
      deviceId: await _resolveDeviceId(logger),
      appVersion: appVersion,
      buildNumber: buildNumber,
      platformDescription: platformDescription,
    );
  }

  static Future<String> _resolveDeviceId(AppLogger logger) async {
    try {
      final Box<String> box = Hive.isBoxOpen(_boxName)
          ? Hive.box<String>(_boxName)
          : await Hive.openBox<String>(_boxName);
      final String? existing = box.get(_deviceIdKey);
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }
      final String generated = _randomId();
      await box.put(_deviceIdKey, generated);
      return generated;
    } catch (error) {
      logger.warning('device_id_persist_failed', error: error);
      // A per-session id is worse than a stable one, but far better than
      // failing to start. It is marked so the audit trail shows what happened.
      return 'ephemeral-${_randomId()}';
    }
  }

  static String _randomId() {
    final Random random = Random.secure();
    return List<String>.generate(
      16,
      (int _) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  @override
  final String deviceId;

  @override
  final String appVersion;

  @override
  final String buildNumber;

  @override
  final String platformDescription;
}
