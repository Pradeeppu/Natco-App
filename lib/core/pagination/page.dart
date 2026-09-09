/// One page of a cursor-based query.
///
/// `nextCursor` is opaque to the caller: an in-memory data source uses an
/// integer offset, a Firestore one a `DocumentSnapshot`. No screen loads an
/// unbounded collection (requirement §42; docs/03-firestore-schema.md
/// "Pagination").
library;

typedef Page<T> = ({List<T> items, Object? nextCursor, bool hasMore});

/// Default page size for a list screen (docs/03-firestore-schema.md).
const int kDefaultPageSize = 25;

/// Upper bound for a Firestore prefix search: `name >= q && name < q + this`.
///
/// U+F8FF sits near the top of the Basic Multilingual Plane's private use
/// area, so it sorts after any character a school or student name will
/// contain. Named here, and written as an escape, because the literal
/// character renders as nothing at all — in an editor, in a diff, and in code
/// review. Dropped by accident, the clause silently becomes `q <= name < q`,
/// which matches no document and turns every search into an empty screen with
/// no error to explain it.
///
/// Always use this constant rather than pasting the character.
const String kPrefixSearchUpperBound = '\uf8ff';
