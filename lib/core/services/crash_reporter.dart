/// Crash and non-fatal error reporting.
///
/// Abstracted so Crashlytics is replaceable, and so tests and demo mode do not
/// need a Firebase project.
///
/// The reporter is given an opaque `userId` and nothing else about a person.
/// No student name, date of birth, email or phone number is ever attached to a
/// report (requirement section 35).
library;

abstract interface class CrashReporter {
  /// Records a non-fatal error with optional non-personal context.
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object?> context = const <String, Object?>{},
    bool fatal = false,
  });

  /// Associates subsequent reports with an opaque user identifier.
  Future<void> setUserId(String? userId);

  /// Sets a low-cardinality key used to slice crash reports, e.g. `role`,
  /// `env`, `omr_processor`. Values must not be personal data.
  Future<void> setCustomKey(String key, Object value);

  /// Leaves a breadcrumb describing what the app was doing.
  Future<void> log(String message);
}

/// Discards everything. Used in tests and in demo mode.
final class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, Object?> context = const <String, Object?>{},
    bool fatal = false,
  }) async {}

  @override
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}

  @override
  Future<void> log(String message) async {}
}
