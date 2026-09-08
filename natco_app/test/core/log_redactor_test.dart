/// Tests for log redaction.
///
/// Requirement section 55 forbids logging passwords, tokens and unnecessary
/// student personal data. Redaction is central rather than per-call-site
/// precisely so it can be tested once, here — including the case that a
/// careless developer logs a whole user object.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/services/log_redactor.dart';

void main() {
  const LogRedactor redactor = LogRedactor();

  group('key detection', () {
    test('matches credential keys in any casing or shape', () {
      for (final String key in <String>[
        'password',
        'Password',
        'PASSWORD',
        'idToken',
        'refresh_token',
        'authToken',
        'apiKey',
        'API_KEY',
        'Authorization',
        'privateKey',
        'sessionKey',
      ]) {
        expect(
          redactor.isSensitiveKey(key),
          isTrue,
          reason: '$key was not treated as sensitive',
        );
      }
    });

    test('matches student and user personal-data keys', () {
      for (final String key in <String>[
        'studentName',
        'student_name',
        'dateOfBirth',
        'dob',
        'email',
        'phone',
        'address',
        'guardianName',
      ]) {
        expect(redactor.isSensitiveKey(key), isTrue, reason: key);
      }
    });

    test('leaves operational keys alone', () {
      for (final String key in <String>[
        'userId',
        'role',
        'schoolId',
        'omrId',
        'questionNumber',
        'confidence',
        'status',
        'attemptCount',
        'code',
      ]) {
        expect(redactor.isSensitiveKey(key), isFalse, reason: key);
      }
    });
  });

  group('redactMap', () {
    test('replaces sensitive values but keeps the key visible', () {
      final Map<String, Object?> result = redactor.redactMap(<String, Object?>{
        'userId': 'u1',
        'password': 'hunter2',
      });
      expect(result['userId'], 'u1');
      expect(result['password'], kRedactedPlaceholder);
      // The key stays so a log line still shows that a field was present.
      expect(result.containsKey('password'), isTrue);
    });

    test('redacts nested maps', () {
      final Map<String, Object?> result = redactor.redactMap(<String, Object?>{
        'session': <String, Object?>{
          'userId': 'u1',
          'idToken': 'eyJhbGciOi...',
          'user': <String, Object?>{
            'role': 'PST_TEACHER',
            'studentName': 'Should not be here',
          },
        },
      });
      final Map<String, Object?> session =
          result['session']! as Map<String, Object?>;
      expect(session['userId'], 'u1');
      expect(session['idToken'], kRedactedPlaceholder);
      final Map<String, Object?> user =
          session['user']! as Map<String, Object?>;
      expect(user['role'], 'PST_TEACHER');
      expect(user['studentName'], kRedactedPlaceholder);
    });

    test('redacts inside lists', () {
      final Map<String, Object?> result = redactor.redactMap(<String, Object?>{
        'students': <Object?>[
          <String, Object?>{'studentId': 's1', 'studentName': 'Ravi'},
          <String, Object?>{'studentId': 's2', 'studentName': 'Meera'},
        ],
      });
      final List<Object?> students = result['students']! as List<Object?>;
      for (final Object? entry in students) {
        final Map<String, Object?> student = entry! as Map<String, Object?>;
        expect(student['studentName'], kRedactedPlaceholder);
        expect(student['studentId'], isNot(kRedactedPlaceholder));
      }
    });

    test('survives a whole user object being logged carelessly', () {
      // This is the failure mode central redaction exists to catch.
      final Map<String, Object?> result = redactor.redactMap(<String, Object?>{
        'userId': 'u1',
        'email': 'teacher@example.org',
        'displayName': 'Suresh Babu',
        'phone': '+910000000000',
        'role': 'PST_TEACHER',
      });
      expect(result.toString(), isNot(contains('teacher@example.org')));
      expect(result.toString(), isNot(contains('Suresh')));
      expect(result.toString(), isNot(contains('+910000000000')));
      expect(result['role'], 'PST_TEACHER');
    });

    test('stops at a depth limit rather than recursing forever', () {
      Object? nested = 'leaf';
      for (int i = 0; i < 30; i++) {
        nested = <String, Object?>{'level': nested};
      }
      final Map<String, Object?> result = redactor.redactMap(<String, Object?>{
        'root': nested,
      });
      expect(result.toString(), contains('depth-limited'));
    });

    test('handles a cyclic structure without hanging', () {
      final Map<String, Object?> cyclic = <String, Object?>{'name': 'loop'};
      cyclic['self'] = cyclic;
      expect(() => redactor.redactMap(cyclic), returnsNormally);
    });

    test('leaves an empty payload empty', () {
      expect(redactor.redactMap(const <String, Object?>{}), isEmpty);
    });
  });

  group('redactMessage', () {
    test('scrubs key=value pairs in free text', () {
      expect(
        redactor.redactMessage('login failed password=hunter2 code=401'),
        'login failed password=[redacted] code=401',
      );
    });

    test('scrubs key: value pairs', () {
      expect(
        redactor.redactMessage('idToken: eyJhbGciOi'),
        contains(kRedactedPlaceholder),
      );
      expect(
        redactor.redactMessage('idToken: eyJhbGciOi'),
        isNot(contains('eyJhbGciOi')),
      );
    });

    test('scrubs quoted values', () {
      final String scrubbed = redactor.redactMessage(
        'body={"email":"a@b.c","role":"VIEWER"}',
      );
      expect(scrubbed, isNot(contains('a@b.c')));
      expect(scrubbed, contains('VIEWER'));
    });

    test('leaves ordinary text untouched', () {
      const String message = 'sync upload failed after 3 attempts';
      expect(redactor.redactMessage(message), message);
    });
  });

  group('a custom fragment set', () {
    test('is honoured', () {
      const LogRedactor custom = LogRedactor(
        sensitiveKeyFragments: <String>{'omrid'},
      );
      final Map<String, Object?> result = custom.redactMap(<String, Object?>{
        'omrId': '0001827',
        'password': 'hunter2',
      });
      expect(result['omrId'], kRedactedPlaceholder);
      // The default set no longer applies, which is the caller's choice.
      expect(result['password'], 'hunter2');
    });
  });
}
