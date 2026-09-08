/// Tests for identifier generation.
///
/// Two properties do real work: idempotency keys must be stable across
/// retries (so a replayed upload is a no-op), and dedupe keys must collide for
/// the same child however the name was typed (so a duplicate import is
/// rejected rather than merged).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/utils/id_generator.dart';

void main() {
  const IdGenerator generator = UuidIdGenerator();

  group('newId', () {
    test('produces distinct identifiers', () {
      final Set<String> ids = <String>{
        for (int i = 0; i < 500; i++) generator.newId(),
      };
      expect(ids, hasLength(500));
    });

    test('produces a UUID-shaped value', () {
      expect(
        generator.newId(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('idempotencyKey', () {
    test('is stable for the same operation, so a retry is a no-op', () {
      String key() => generator.idempotencyKey(
        entityType: 'omr_submission',
        entityId: 'sub-1',
        operation: 'CREATE',
        revision: 1,
      );
      expect(key(), key());
    });

    test('differs when any coordinate differs', () {
      final String base = generator.idempotencyKey(
        entityType: 'omr_submission',
        entityId: 'sub-1',
        operation: 'CREATE',
        revision: 1,
      );
      expect(
        generator.idempotencyKey(
          entityType: 'omr_answer',
          entityId: 'sub-1',
          operation: 'CREATE',
          revision: 1,
        ),
        isNot(base),
      );
      expect(
        generator.idempotencyKey(
          entityType: 'omr_submission',
          entityId: 'sub-2',
          operation: 'CREATE',
          revision: 1,
        ),
        isNot(base),
      );
      expect(
        generator.idempotencyKey(
          entityType: 'omr_submission',
          entityId: 'sub-1',
          operation: 'UPDATE',
          revision: 1,
        ),
        isNot(base),
      );
      expect(
        generator.idempotencyKey(
          entityType: 'omr_submission',
          entityId: 'sub-1',
          operation: 'CREATE',
          revision: 2,
        ),
        isNot(base),
      );
    });

    test('is a hex digest, safe as a document id', () {
      expect(
        generator.idempotencyKey(
          entityType: 'a',
          entityId: 'b',
          operation: 'c',
          revision: 1,
        ),
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    });
  });

  group('dedupeKey', () {
    List<String> student(String name) => <String>[
      'sch1',
      name,
      '5',
      'A',
      '2015-04-02',
    ];

    test('collides for the same child typed differently', () {
      // Requirement section 11: prevent duplicate student records.
      final String canonical = generator.dedupeKey(student('Ravi Kumar'));
      for (final String variant in <String>[
        'ravi kumar',
        'RAVI KUMAR',
        '  Ravi   Kumar  ',
        'Ravi Kumar.',
        'Ravi, Kumar',
      ]) {
        expect(
          generator.dedupeKey(student(variant)),
          canonical,
          reason: '"$variant" produced a different key',
        );
      }
    });

    test('differs for a different child', () {
      expect(
        generator.dedupeKey(student('Ravi Kumari')),
        isNot(generator.dedupeKey(student('Ravi Kumar'))),
      );
    });

    test('differs across schools', () {
      expect(
        generator.dedupeKey(<String>['sch2', 'Ravi Kumar', '5', 'A', '2015']),
        isNot(
          generator.dedupeKey(<String>['sch1', 'Ravi Kumar', '5', 'A', '2015']),
        ),
      );
    });

    test('handles non-Latin names without collapsing them', () {
      expect(
        generator.dedupeKey(student('रवि कुमार')),
        isNot(generator.dedupeKey(student('रवि कुमारी'))),
      );
      // Unicode letters survive normalisation; only punctuation is stripped.
      expect(
        generator.dedupeKey(student('रवि कुमार')),
        isNot(generator.dedupeKey(student(''))),
      );
    });

    test('keeps Indic vowel signs, which are marks rather than letters', () {
      // Regression: a normaliser that kept only letters and digits stripped
      // the mātrā, turning रवि into रव and कुमार into कमर. Two different
      // children then produced the same key and the second import was
      // rejected as a duplicate.
      expect(
        generator.dedupeKey(student('रवि')),
        isNot(generator.dedupeKey(student('रव'))),
      );
      expect(
        generator.dedupeKey(student('कुमार')),
        isNot(generator.dedupeKey(student('कमर'))),
      );
      // The same holds for other Indic scripts.
      expect(
        generator.dedupeKey(student('ரவி')),
        isNot(generator.dedupeKey(student('ரவ'))),
      );
    });

    test('is order-sensitive, so grade and section cannot be swapped', () {
      expect(
        generator.dedupeKey(<String>['sch1', 'Ravi', 'A', '5']),
        isNot(generator.dedupeKey(<String>['sch1', 'Ravi', '5', 'A'])),
      );
    });
  });

  group('SequentialIdGenerator', () {
    test('produces predictable ids for tests', () {
      final IdGenerator sequential = SequentialIdGenerator('omr');
      expect(sequential.newId(), 'omr-1');
      expect(sequential.newId(), 'omr-2');
    });

    test('hashes identically to the production generator', () {
      // So a test that pins an idempotency key stays valid in production.
      final IdGenerator sequential = SequentialIdGenerator();
      expect(
        sequential.dedupeKey(<String>['a', 'b']),
        generator.dedupeKey(<String>['a', 'b']),
      );
      expect(
        sequential.idempotencyKey(
          entityType: 'a',
          entityId: 'b',
          operation: 'c',
          revision: 1,
        ),
        generator.idempotencyKey(
          entityType: 'a',
          entityId: 'b',
          operation: 'c',
          revision: 1,
        ),
      );
    });
  });

  group('stability across releases', () {
    test('the same inputs always hash to the same output', () {
      // Dedupe keys are stored server-side as document ids. A change to the
      // hash or the normaliser would orphan every existing guard document and
      // silently re-admit duplicates, so the digest is pinned here: this test
      // failing means a migration is required, not that the value needs
      // updating.
      const String pinned =
          'e6c99b39698fb0e57651104efb5d926b036bbd1e69effc72df4db499cfc57f41';
      expect(
        generator.dedupeKey(<String>['sch1', 'Ravi Kumar', '5', 'A']),
        pinned,
      );
    });
  });
}
