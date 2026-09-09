/// Client-side identifier generation.
///
/// Records created offline own their identity from the moment they exist. The
/// server never renames them, which is what lets a retried upload be a no-op
/// instead of a duplicate (docs/06-offline-sync-strategy.md).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

abstract interface class IdGenerator {
  /// A fresh opaque identifier.
  String newId();

  /// A stable idempotency key for a sync operation.
  ///
  /// The same logical operation must produce the same key on every retry, so
  /// it is derived from the operation's coordinates rather than randomly.
  String idempotencyKey({
    required String entityType,
    required String entityId,
    required String operation,
    required int revision,
  });

  /// Deterministic duplicate-detection key.
  ///
  /// Used for `student_dedupe`: two imports of the same child in the same
  /// school must collide rather than create twins (requirement section 11).
  String dedupeKey(List<String> parts);
}

final class UuidIdGenerator implements IdGenerator {
  const UuidIdGenerator([this._uuid = const Uuid()]);

  final Uuid _uuid;

  @override
  String newId() => _uuid.v4();

  @override
  String idempotencyKey({
    required String entityType,
    required String entityId,
    required String operation,
    required int revision,
  }) => _sha256('$entityType|$entityId|$operation|$revision');

  @override
  String dedupeKey(List<String> parts) =>
      _sha256(parts.map(_normalise).join('|'));

  /// Lowercases, collapses internal whitespace and strips punctuation so that
  /// "Ravi  Kumar." and "ravi kumar" produce the same key.
  ///
  /// The character class keeps combining marks (`\p{M}`) as well as letters
  /// and digits, and that is not incidental. Indic vowel signs — the mātrā in
  /// रवि or कुमार — are marks, not letters. A class of letters and digits alone
  /// strips them, turning रवि into रव and कुमार into कमर, which would collapse
  /// genuinely different children onto one dedupe key and reject the second
  /// one as a duplicate. For a product used in Indian schools that is a
  /// data-integrity failure, not a cosmetic one.
  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}

/// Deterministic generator for tests: predictable ids, same hashing.
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator([this._prefix = 'id']);

  final String _prefix;
  int _counter = 0;

  @override
  String newId() => '$_prefix-${++_counter}';

  @override
  String idempotencyKey({
    required String entityType,
    required String entityId,
    required String operation,
    required int revision,
  }) => const UuidIdGenerator().idempotencyKey(
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    revision: revision,
  );

  @override
  String dedupeKey(List<String> parts) =>
      const UuidIdGenerator().dedupeKey(parts);
}
