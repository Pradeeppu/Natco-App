/// Structured logging.
///
/// Logs are records, not `print` statements: a level, an event name, and a
/// map of fields. That shape is what lets sync failures and OMR processing
/// failures be searched and counted later instead of read one line at a time.
///
/// Every payload passes through [LogRedactor] before it reaches a sink, so
/// there is no code path that emits a password, a token or a student's name
/// (requirement section 55).
library;

import 'dart:developer' as developer;

import 'package:natco_app/core/services/log_redactor.dart';

enum LogLevel {
  debug(500, 'DEBUG'),
  info(800, 'INFO'),
  warning(900, 'WARN'),
  error(1000, 'ERROR');

  const LogLevel(this.severity, this.label);

  final int severity;
  final String label;

  bool operator >=(LogLevel other) => severity >= other.severity;
}

/// One structured log record.
final class LogRecord {
  const LogRecord({
    required this.level,
    required this.event,
    required this.timestamp,
    this.fields = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  final LogLevel level;

  /// Snake-case event name, e.g. `sync_upload_failed`. Stable across releases
  /// so it can be counted.
  final String event;

  final DateTime timestamp;
  final Map<String, Object?> fields;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final String suffix = fields.isEmpty
        ? ''
        : ' ${fields.entries.map((MapEntry<String, Object?> e) => '${e.key}=${e.value}').join(' ')}';
    return '[${level.label}] $event$suffix';
  }
}

/// Destination for log records.
abstract interface class LogSink {
  void write(LogRecord record);
}

/// Writes to the Dart developer log. Used in development.
final class DeveloperLogSink implements LogSink {
  const DeveloperLogSink();

  @override
  void write(LogRecord record) {
    developer.log(
      record.toString(),
      name: 'natco',
      level: record.level.severity,
      time: record.timestamp,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}

/// Keeps records in memory. Used by tests and by the in-app diagnostics
/// screen, which is how a field user exports a log without a cable.
final class InMemoryLogSink implements LogSink {
  InMemoryLogSink({this.capacity = 500});

  final int capacity;
  final List<LogRecord> _records = <LogRecord>[];

  List<LogRecord> get records => List<LogRecord>.unmodifiable(_records);

  @override
  void write(LogRecord record) {
    _records.add(record);
    if (_records.length > capacity) {
      _records.removeRange(0, _records.length - capacity);
    }
  }

  void clear() => _records.clear();
}

/// The application logger.
final class AppLogger {
  AppLogger({
    required this.minimumLevel,
    this.sinks = const <LogSink>[DeveloperLogSink()],
    this.redactor = const LogRedactor(),
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  /// Records below this level are dropped before redaction or formatting.
  final LogLevel minimumLevel;

  final List<LogSink> sinks;

  /// Applied to every record. There is no path around it.
  final LogRedactor redactor;

  final DateTime Function() _now;

  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.debug, event, fields: fields);

  void info(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.info, event, fields: fields);

  void warning(
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
  }) => _log(LogLevel.warning, event, fields: fields, error: error);

  void error(
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _log(
    LogLevel.error,
    event,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  void _log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!(level >= minimumLevel)) {
      return;
    }
    final LogRecord record = LogRecord(
      level: level,
      event: event,
      timestamp: _now(),
      fields: redactor.redactMap(fields),
      // The error object itself can carry a message with interpolated data,
      // so it is stringified through the redactor rather than passed straight
      // to the sink.
      error: error == null ? null : redactor.redactMessage(error.toString()),
      stackTrace: stackTrace,
    );
    for (final LogSink sink in sinks) {
      sink.write(record);
    }
  }
}
