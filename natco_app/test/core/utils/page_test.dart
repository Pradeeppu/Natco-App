/// Tests for the cursor-based pagination primitive.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/utils/page.dart';

void main() {
  group('PageRequest', () {
    test('defaults to the standard page size and no cursor', () {
      const PageRequest request = PageRequest();
      expect(request.limit, kDefaultPageSize);
      expect(request.cursor, isNull);
    });

    test('first is the same as an unparameterised request', () {
      expect(PageRequest.first.limit, kDefaultPageSize);
      expect(PageRequest.first.cursor, isNull);
    });

    test('withCursor keeps the limit and swaps only the cursor', () {
      const PageRequest request = PageRequest(limit: 10, cursor: 'a');
      final PageRequest next = request.withCursor('b');
      expect(next.limit, 10);
      expect(next.cursor, 'b');
    });
  });

  group('Page', () {
    test('empty has no items and no cursor', () {
      const Page<int> page = Page<int>.empty();
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
      expect(page.isEmpty, isTrue);
    });

    test('hasMore is true only when a next cursor is present', () {
      const Page<int> withMore = Page<int>(items: <int>[1, 2], nextCursor: '2');
      const Page<int> last = Page<int>(items: <int>[3], nextCursor: null);
      expect(withMore.hasMore, isTrue);
      expect(last.hasMore, isFalse);
    });

    test('map transforms items and keeps the cursor', () {
      const Page<int> page = Page<int>(items: <int>[1, 2, 3], nextCursor: '3');
      final Page<String> mapped = page.map((int i) => 'n$i');
      expect(mapped.items, <String>['n1', 'n2', 'n3']);
      expect(mapped.nextCursor, '3');
    });
  });
}
