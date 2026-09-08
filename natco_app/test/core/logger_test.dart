/// Tests for the structured logger.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/services/log_redactor.dart';
import 'package:natco_app/core/services/logger.dart';

void main() {
  late InMemoryLogSink sink;

  setUp(() => sink = InMemoryLogSink());

  AppLogger buildLogger(LogLevel minimum) => AppLogger(
    minimumLevel: minimum,
    sinks: <LogSink>[sink],
    now: () => DateTime.utc(2026, 9, 8, 10, 42),
  );

  group('level filtering', () {
    test('drops records below the minimum level', () {
      final AppLogger logger = buildLogger(LogLevel.warning);
      logger.debug('debug_event');
      logger.info('info_event');
      logger.warning('warning_event');
      logger.error('error_event');
      expect(sink.records.map((LogRecord r) => r.event), <String>[
        'warning_event',
        'error_event',
      ]);
    });

    test('emits everything at debug level', () {
      final AppLogger logger = buildLogger(LogLevel.debug);
      logger.debug('a');
      logger.info('b');
      logger.warning('c');
      logger.error('d');
      expect(sink.records, hasLength(4));
    });
  });

  group('redaction on the way out', () {
    test('applies to structured fields', () {
      final AppLogger logger = buildLogger(LogLevel.debug);
      logger.info(
        'sign_in_attempt',
        fields: <String, Object?>{
          'email': 'teacher@example.org',
          'role': 'PST_TEACHER',
        },
      );
      final LogRecord record = sink.records.single;
      expect(record.fields['email'], kRedactedPlaceholder);
      expect(record.fields['role'], 'PST_TEACHER');
    });

    test('applies to an error object, which can carry interpolated data', () {
      final AppLogger logger = buildLogger(LogLevel.debug);
      logger.error('request_failed', error: StateError('token=abc123 failed'));
      expect(sink.records.single.error.toString(), isNot(contains('abc123')));
    });

    test('has no path that bypasses it', () {
      // Every entry point funnels through the same private _log.
      final AppLogger logger = buildLogger(LogLevel.debug);
      logger.debug('e', fields: <String, Object?>{'password': 'p'});
      logger.info('e', fields: <String, Object?>{'password': 'p'});
      logger.warning('e', fields: <String, Object?>{'password': 'p'});
      logger.error('e', fields: <String, Object?>{'password': 'p'});
      for (final LogRecord record in sink.records) {
        expect(record.fields['password'], kRedactedPlaceholder);
      }
    });
  });

  group('records', () {
    test('carry the injected timestamp, in UTC', () {
      buildLogger(LogLevel.debug).info('event');
      expect(sink.records.single.timestamp, DateTime.utc(2026, 9, 8, 10, 42));
      expect(sink.records.single.timestamp.isUtc, isTrue);
    });

    test('render event and fields for a sink', () {
      buildLogger(LogLevel.debug).info(
        'sync_upload_failed',
        fields: <String, Object?>{'attemptCount': 3, 'code': 'timeout'},
      );
      final String rendered = sink.records.single.toString();
      expect(rendered, contains('[INFO]'));
      expect(rendered, contains('sync_upload_failed'));
      expect(rendered, contains('attemptCount=3'));
      expect(rendered, contains('code=timeout'));
    });

    test('render without a trailing separator when there are no fields', () {
      buildLogger(LogLevel.debug).info('plain_event');
      expect(sink.records.single.toString(), '[INFO] plain_event');
    });
  });

  group('InMemoryLogSink', () {
    test('keeps only the most recent records', () {
      final InMemoryLogSink bounded = InMemoryLogSink(capacity: 3);
      final AppLogger logger = AppLogger(
        minimumLevel: LogLevel.debug,
        sinks: <LogSink>[bounded],
      );
      for (int i = 0; i < 10; i++) {
        logger.info('event_$i');
      }
      expect(bounded.records, hasLength(3));
      expect(bounded.records.map((LogRecord r) => r.event), <String>[
        'event_7',
        'event_8',
        'event_9',
      ]);
    });

    test('clears', () {
      buildLogger(LogLevel.debug).info('event');
      sink.clear();
      expect(sink.records, isEmpty);
    });
  });

  test('writes to every configured sink', () {
    final InMemoryLogSink second = InMemoryLogSink();
    AppLogger(
      minimumLevel: LogLevel.debug,
      sinks: <LogSink>[sink, second],
    ).info('event');
    expect(sink.records, hasLength(1));
    expect(second.records, hasLength(1));
  });
}
