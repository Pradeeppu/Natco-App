/// Shared helpers for Firestore-backed repositories.
///
/// Kept separate from any one repository because every Firestore
/// implementation in this app needs the same three things: turning a
/// snapshot into the JSON shape the domain's `tryFromJson` methods expect,
/// mapping Firestore's own exceptions onto [Failure], and a consistent
/// pagination cursor scheme.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/errors/failure.dart';

/// Converts a Firestore document into the JSON map shape used across this
/// app's domain entities — in particular, [Timestamp] becomes an ISO-8601
/// UTC string, matching what every `tryFromJson` method expects.
///
/// Without this, every entity would need two parsing paths: one for JSON
/// (tests, local cache) and one for Firestore's native types. One path is
/// what keeps `School.tryFromJson` usable from both.
Map<String, Object?> firestoreDocToJson(Map<String, Object?> data) =>
    data.map(
      (String key, Object? value) =>
          MapEntry<String, Object?>(key, _normaliseValue(value)),
    );

Object? _normaliseValue(Object? value) => switch (value) {
  final Timestamp timestamp => timestamp.toDate().toUtc().toIso8601String(),
  final Map<String, Object?> nested => firestoreDocToJson(nested),
  final List<Object?> list =>
    list.map(_normaliseValue).toList(growable: false),
  _ => value,
};

/// Maps a raw Firestore error to a domain [Failure].
///
/// Mirrors `FirebaseAuthService._mapFirestoreError` — kept here too because
/// every Firestore-backed repository needs the same mapping, and duplicating
/// it per repository is how the mappings drift apart over time.
Failure mapFirestoreError(Object error, StackTrace stackTrace) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => PermissionFailure.denied(
        diagnostic: 'firestore permission-denied',
      ),
      'unavailable' || 'network-request-failed' => NetworkFailure.unreachable(
        diagnostic: error.code,
        cause: error,
      ),
      'deadline-exceeded' => NetworkFailure.timeout(diagnostic: error.code),
      'aborted' => ConflictFailure(
        userMessage:
            'This record was changed at the same time elsewhere. '
            'Please try again.',
        entityType: 'unknown',
        entityId: 'unknown',
        localRevision: 0,
        serverRevision: 0,
        diagnostic: error.code,
      ),
      _ => UnexpectedFailure(
        diagnostic: 'FirebaseException ${error.code}',
        cause: error,
        stackTrace: stackTrace,
      ),
    };
  }
  return UnexpectedFailure(
    diagnostic: error.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}

/// The exclusive upper bound for a Firestore "starts with [prefix]" range
/// query: `where(field, isGreaterThanOrEqualTo: prefix).where(field,
/// isLessThan: firestorePrefixUpperBound(prefix))`.
///
/// Firestore has no native prefix operator, so a prefix search is expressed
/// as a value range. The upper bound must be strictly greater than every
/// string that starts with [prefix] — using [prefix] itself here (a bug this
/// file used to have) makes the range `>= prefix AND < prefix`, which is
/// empty by construction and matches nothing. Appending U+F8FF, the last
/// code point in the Unicode Private Use Area and higher than any character
/// in ordinary text, is the standard fix: no real name sorts after it.
String firestorePrefixUpperBound(String prefix) => '$prefix\u{f8ff}';

/// A value-based pagination cursor encoding an order-by value paired with a
/// document id, joined by a control character no real field value can
/// contain.
///
/// Firestore pagination is usually shown via `startAfterDocument`, which
/// needs a live `DocumentSnapshot` in hand. That is awkward for this app's
/// domain-level `PageRequest.cursor`, which is a plain opaque string that
/// outlives any one screen or provider rebuild. A composite value cursor —
/// the order-by field's value plus the document id, to break ties — needs
/// nothing but the string itself to resume a query with
/// `.startAfter([orderValue, docId])`, which is what every repository here
/// uses instead.
///
/// The join character is a control character rather than a printable one
/// such as a space: an order-by value here is a school or student *name*,
/// which routinely contains spaces ("Green Valley School"), so a printable
/// separator risks colliding with real data. `String.fromCharCode(0)` (NUL)
/// cannot appear in a name a human typed.
final class FirestoreCursor {
  const FirestoreCursor({required this.orderValue, required this.documentId});

  static final String _join = String.fromCharCode(0);

  final String orderValue;
  final String documentId;

  String encode() => '$orderValue$_join$documentId';

  static FirestoreCursor? tryDecode(String? raw) {
    if (raw == null) {
      return null;
    }
    final int splitAt = raw.indexOf(_join);
    if (splitAt == -1) {
      return null;
    }
    return FirestoreCursor(
      orderValue: raw.substring(0, splitAt),
      documentId: raw.substring(splitAt + 1),
    );
  }
}
