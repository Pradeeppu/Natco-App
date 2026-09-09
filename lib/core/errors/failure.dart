/// Typed failures for the NATCO domain layer.
///
/// Repositories return [Failure] values instead of throwing for any condition
/// the product has an answer for. Throwing is reserved for programmer error.
///
/// Every failure carries two messages, and the split is deliberate:
///
/// * [userMessage] is what a teacher standing in a classroom reads. It never
///   contains an exception name, a stack frame, or a Firebase error code
///   (requirement section 40).
/// * [diagnostic] is what goes to the structured logger and the crash
///   reporter. It is never rendered on screen.
library;

/// Stable machine-readable code for a failure, used in logs, audit entries and
/// sync-queue records so a support engineer can correlate a report with a log
/// line without relying on message text.
enum FailureCode {
  network,
  timeout,
  offline,
  unauthenticated,
  sessionExpired,
  accountDisabled,
  invalidCredentials,
  permissionDenied,
  outOfScope,
  validation,
  duplicate,
  conflict,
  notFound,
  storage,
  imageQuality,
  omrProcessing,
  illegalStateTransition,
  configuration,
  unexpected,
}

/// Base type for every expected failure in the system.
sealed class Failure {
  const Failure({
    required this.code,
    required this.userMessage,
    this.diagnostic,
    this.cause,
    this.stackTrace,
  });

  /// Stable identifier for logs and audit records.
  final FailureCode code;

  /// Plain-language, actionable text safe to show in the UI.
  final String userMessage;

  /// Technical detail for logs only. Must never reach the screen.
  final String? diagnostic;

  /// Underlying error, if this failure wraps one.
  final Object? cause;

  final StackTrace? stackTrace;

  /// Whether retrying the same operation unchanged could plausibly succeed.
  ///
  /// The sync engine uses this to decide between backoff and surfacing the
  /// entry to a human. Retrying a `permissionDenied` forever looks like a bug
  /// to the user and hides the real problem.
  bool get isRetryable => switch (code) {
    FailureCode.network ||
    FailureCode.timeout ||
    FailureCode.offline ||
    FailureCode.sessionExpired ||
    FailureCode.storage => true,
    _ => false,
  };

  @override
  String toString() => '$runtimeType(${code.name}): $userMessage';
}

/// The device could not reach the server, or the request timed out.
final class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.code,
    required super.userMessage,
    super.diagnostic,
    super.cause,
    super.stackTrace,
  });

  /// No usable connection. Field default: reassure that nothing was lost.
  factory NetworkFailure.offline({String? diagnostic}) => NetworkFailure(
    code: FailureCode.offline,
    userMessage:
        'You are offline. Your work is saved on this device and will be '
        'uploaded automatically when a connection is available.',
    diagnostic: diagnostic,
  );

  factory NetworkFailure.timeout({String? diagnostic}) => NetworkFailure(
    code: FailureCode.timeout,
    userMessage: 'The server took too long to respond. Please try again.',
    diagnostic: diagnostic,
  );

  factory NetworkFailure.unreachable({String? diagnostic, Object? cause}) =>
      NetworkFailure(
        code: FailureCode.network,
        userMessage:
            'Unable to reach the server. Your data is safely stored on this '
            'device.',
        diagnostic: diagnostic,
        cause: cause,
      );
}

/// Sign-in and session problems.
final class AuthFailure extends Failure {
  const AuthFailure({
    required super.code,
    required super.userMessage,
    super.diagnostic,
    super.cause,
    super.stackTrace,
  });

  factory AuthFailure.invalidCredentials({String? diagnostic}) => AuthFailure(
    code: FailureCode.invalidCredentials,
    // Deliberately does not say which of the two was wrong: telling an
    // attacker that an email exists is an account-enumeration gift.
    userMessage: 'Incorrect email or password. Please check and try again.',
    diagnostic: diagnostic,
  );

  factory AuthFailure.accountDisabled({String? diagnostic}) => AuthFailure(
    code: FailureCode.accountDisabled,
    userMessage:
        'This account has been deactivated. Please contact your administrator.',
    diagnostic: diagnostic,
  );

  factory AuthFailure.sessionExpired({String? diagnostic}) => AuthFailure(
    code: FailureCode.sessionExpired,
    userMessage:
        'Your offline session has expired. Please sign in again while '
        'connected to the internet.',
    diagnostic: diagnostic,
  );

  factory AuthFailure.unauthenticated({String? diagnostic}) => AuthFailure(
    code: FailureCode.unauthenticated,
    userMessage: 'Please sign in to continue.',
    diagnostic: diagnostic,
  );

  factory AuthFailure.tooManyAttempts({String? diagnostic}) => AuthFailure(
    code: FailureCode.invalidCredentials,
    userMessage:
        'Too many sign-in attempts. Please wait a few minutes and try again.',
    diagnostic: diagnostic,
  );
}

/// The caller's role lacks the permission, or the target is outside the
/// caller's geographic scope.
final class PermissionFailure extends Failure {
  const PermissionFailure({
    required super.code,
    required super.userMessage,
    super.diagnostic,
    super.cause,
    super.stackTrace,
  });

  factory PermissionFailure.denied({String? action, String? diagnostic}) =>
      PermissionFailure(
        code: FailureCode.permissionDenied,
        userMessage: action == null
            ? 'You do not have permission to do this.'
            : 'You do not have permission to $action.',
        diagnostic: diagnostic,
      );

  factory PermissionFailure.outOfScope({String? diagnostic}) =>
      PermissionFailure(
        code: FailureCode.outOfScope,
        userMessage: 'You do not have access to this school.',
        diagnostic: diagnostic,
      );
}

/// Input or business-rule validation failed.
final class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.userMessage,
    this.fieldErrors = const <String, String>{},
    super.code = FailureCode.validation,
    super.diagnostic,
    super.cause,
    super.stackTrace,
  });

  /// Field name to message, for inline form errors.
  final Map<String, String> fieldErrors;
}

/// A uniqueness guard rejected the write.
final class DuplicateFailure extends Failure {
  const DuplicateFailure({
    required super.userMessage,
    required this.entityType,
    required this.entityId,
    this.details = const <String, String>{},
    super.code = FailureCode.duplicate,
    super.diagnostic,
  });

  final String entityType;
  final String entityId;

  /// Human-readable detail about the existing record, so the UI can show
  /// "previous submission: school, date, time" rather than a bare rejection
  /// (requirement section 22).
  final Map<String, String> details;
}

/// Local and server versions diverged. Never resolved automatically.
final class ConflictFailure extends Failure {
  const ConflictFailure({
    required super.userMessage,
    required this.entityType,
    required this.entityId,
    required this.localRevision,
    required this.serverRevision,
    super.code = FailureCode.conflict,
    super.diagnostic,
  });

  final String entityType;
  final String entityId;
  final int localRevision;
  final int serverRevision;
}

/// Reading or writing local/remote storage failed.
final class StorageFailure extends Failure {
  const StorageFailure({
    required super.userMessage,
    super.code = FailureCode.storage,
    super.diagnostic,
    super.cause,
    super.stackTrace,
  });

  factory StorageFailure.localWrite({String? diagnostic, Object? cause}) =>
      StorageFailure(
        userMessage:
            'Unable to save to this device. Free up some storage space and '
            'try again.',
        diagnostic: diagnostic,
        cause: cause,
      );

  factory StorageFailure.uploadFailed({String? diagnostic, Object? cause}) =>
      StorageFailure(
        userMessage:
            'Unable to upload. Your data is safely stored on this device and '
            'will be retried.',
        diagnostic: diagnostic,
        cause: cause,
      );
}

/// The requested entity does not exist.
final class NotFoundFailure extends Failure {
  const NotFoundFailure({
    required super.userMessage,
    required this.entityType,
    required this.entityId,
    super.code = FailureCode.notFound,
    super.diagnostic,
  });

  final String entityType;
  final String entityId;
}

/// An entity was asked to move to a state it cannot legally reach.
///
/// This is a real, expected condition — a retried sync or a resumed screen can
/// request a transition that has already happened. It is rejected and logged
/// rather than applied (requirement section 47).
final class IllegalStateTransitionFailure extends Failure {
  const IllegalStateTransitionFailure({
    required this.entityType,
    required this.from,
    required this.to,
    super.code = FailureCode.illegalStateTransition,
    super.userMessage =
        'This item cannot move to that state. Refresh and try again.',
    super.diagnostic,
  });

  final String entityType;
  final String from;
  final String to;
}

/// Environment or configuration is missing/invalid.
final class ConfigurationFailure extends Failure {
  const ConfigurationFailure({
    required super.userMessage,
    super.code = FailureCode.configuration,
    super.diagnostic,
  });
}

/// Nothing else matched. Always logged with its cause.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({
    super.code = FailureCode.unexpected,
    super.userMessage =
        'Something went wrong. Your data is safe. Please try again.',
    super.diagnostic,
    super.cause,
    super.stackTrace,
  });
}
