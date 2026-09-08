/// Crashlytics implementation of [CrashReporter].
///
/// The only file that imports `firebase_crashlytics`. It forwards an opaque
/// user id and low-cardinality keys, and nothing else about a person
/// (requirement section 35).
library;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:natco_app/core/services/crash_reporter.dart';

final class FirebaseCrashReporter implements CrashReporter {
  const FirebaseCrashReporter({required FirebaseCrashlytics crashlytics})
    : _crashlytics = crashlytics;

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object?> context = const <String, Object?>{},
    bool fatal = false,
  }) async {
    for (final MapEntry<String, Object?> entry in context.entries) {
      final Object? value = entry.value;
      if (value != null) {
        await _crashlytics.setCustomKey(entry.key, value);
      }
    }
    await _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  @override
  Future<void> setUserId(String? userId) =>
      _crashlytics.setUserIdentifier(userId ?? '');

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _crashlytics.setCustomKey(key, value);

  @override
  Future<void> log(String message) => _crashlytics.log(message);
}
