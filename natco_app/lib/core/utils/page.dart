/// Cursor-based pagination.
///
/// Requirement section 42: no screen loads an unbounded collection. A 2,000-
/// student school is scrolled, not loaded — every list query in this app goes
/// through this type rather than returning a bare `List<T>`.
library;

/// A request for one page of a list.
final class PageRequest {
  const PageRequest({this.limit = kDefaultPageSize, this.cursor});

  /// Maximum items to return. Matches `AppConfig.listPageSize` by default.
  final int limit;

  /// Opaque continuation token from a previous [Page.nextCursor]. `null`
  /// requests the first page.
  final String? cursor;

  /// The first page at the default size.
  static const PageRequest first = PageRequest();

  PageRequest withCursor(String? cursor) =>
      PageRequest(limit: limit, cursor: cursor);
}

/// Default page size for list screens (requirement section 42; matches
/// `AppConfig.listPageSize`).
const int kDefaultPageSize = 25;

/// One page of results.
final class Page<T> {
  const Page({required this.items, required this.nextCursor});

  /// An empty, terminal page. Useful as a safe default and in tests.
  const Page.empty() : items = const [], nextCursor = null;

  final List<T> items;

  /// Pass to the next [PageRequest] to continue. `null` means this was the
  /// last page.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  bool get isEmpty => items.isEmpty;

  Page<R> map<R>(R Function(T item) transform) =>
      Page<R>(items: items.map(transform).toList(growable: false), nextCursor: nextCursor);
}
