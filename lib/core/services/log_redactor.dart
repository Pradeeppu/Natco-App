/// Removes sensitive values from anything on its way to a log sink.
///
/// Requirement section 55 forbids logging passwords, tokens and unnecessary
/// student personal data. Relying on every call site to remember that is a
/// losing strategy — one `log.info(user.toJson())` is enough to leak. So
/// redaction happens centrally, on the way out, and the logger has no path
/// that bypasses it.
library;

/// Keys whose values are dropped entirely, matched case-insensitively and
/// also as substrings (so `idToken`, `refresh_token` and `authToken` all
/// match `token`).
const Set<String> kSensitiveKeyFragments = <String>{
  'password',
  'passwd',
  'secret',
  'token',
  'credential',
  'apikey',
  'api_key',
  'authorization',
  'cookie',
  'sessionkey',
  'privatekey',
  // Student and user personal data (requirement section 35).
  'studentname',
  'student_name',
  'displayname',
  'display_name',
  'dateofbirth',
  'date_of_birth',
  'dob',
  'email',
  'phone',
  'mobile',
  'address',
  'aadhaar',
  'guardianname',
  'parentname',
};

/// The literal written in place of a removed value, so a log line still shows
/// that a field was present.
const String kRedactedPlaceholder = '[redacted]';

/// Maximum depth walked into nested structures. Beyond this the value is
/// replaced with a type marker, which keeps a cyclic or pathological object
/// from turning a log call into a hang.
const int kMaxRedactionDepth = 6;

/// Redacts sensitive entries from a log payload.
final class LogRedactor {
  const LogRedactor({
    Set<String> sensitiveKeyFragments = kSensitiveKeyFragments,
  }) : _fragments = sensitiveKeyFragments;

  final Set<String> _fragments;

  /// Returns a copy of [payload] with sensitive values replaced.
  Map<String, Object?> redactMap(Map<String, Object?> payload) {
    final Object? result = _redact(payload, 0);
    return result is Map<String, Object?>
        ? result
        : <String, Object?>{'value': result};
  }

  /// Redacts a free-text message.
  ///
  /// Structured fields are the intended way to log data, but messages get
  /// interpolated in practice, so obvious `key=value` and `key: value` pairs
  /// are scrubbed too.
  String redactMessage(String message) {
    var scrubbed = message;
    for (final String fragment in _fragments) {
      scrubbed = scrubbed.replaceAllMapped(
        RegExp(
          // 1: the key, possibly with a prefix or suffix (idToken, api_key).
          '([A-Za-z_]*$fragment[A-Za-z_]*)'
          // 2: an optional closing quote (JSON keys) then the separator.
          r'("?\s*[=:]\s*)'
          // 3: the value — quoted, or up to the next delimiter.
          r"""("[^"]*"|'[^']*'|[^\s,;}\]]+)""",
          caseSensitive: false,
        ),
        (Match match) =>
            '${match.group(1)}${match.group(2)}$kRedactedPlaceholder',
      );
    }
    return scrubbed;
  }

  /// Whether [key] names a value that must not be logged.
  bool isSensitiveKey(String key) {
    final String normalised = key.toLowerCase().replaceAll(
      RegExp(r'[\s\-]'),
      '',
    );
    return _fragments.any(normalised.contains);
  }

  Object? _redact(Object? value, int depth) {
    if (depth > kMaxRedactionDepth) {
      return '[depth-limited ${value.runtimeType}]';
    }
    return switch (value) {
      final Map<Object?, Object?> map => <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in map.entries)
          entry.key.toString(): isSensitiveKey(entry.key.toString())
              ? kRedactedPlaceholder
              : _redact(entry.value, depth + 1),
      },
      final Iterable<Object?> list => <Object?>[
        for (final Object? item in list) _redact(item, depth + 1),
      ],
      final String text => redactMessage(text),
      _ => value,
    };
  }
}
