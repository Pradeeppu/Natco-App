/// Tests for [PagedListController]: initial load, debounced search,
/// load-more accumulation, a load-more failure that keeps existing items,
/// and dropping a stale response superseded by a newer query.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';

typedef _Responder =
    Future<Result<Page<int>>> Function(String query, Object? cursor);

final class _FakeController extends PagedListController<int> {
  _FakeController(this._responder);

  final _Responder _responder;

  @override
  Future<Result<Page<int>>> fetchPage({
    required String query,
    required Object? cursor,
  }) => _responder(query, cursor);
}

final AsyncNotifierProvider<_FakeController, PagedListState<int>> _provider =
    AsyncNotifierProvider<_FakeController, PagedListState<int>>(
      () => _FakeController(
        (String q, Object? c) async =>
            ok((items: const <int>[], nextCursor: null, hasMore: false)),
      ),
    );

ProviderContainer _containerWith(_Responder responder) {
  // The list type is inferred: Riverpod 3 does not export `Override` from
  // `package:flutter_riverpod`, so it cannot be named here.
  final ProviderContainer container = ProviderContainer(
    overrides: [_provider.overrideWith(() => _FakeController(responder))],
  );
  return container;
}

void main() {
  group('initial load', () {
    test('build fetches the first page with an empty query', () async {
      final ProviderContainer container = _containerWith(
        (String query, Object? cursor) async => ok((
          items: const <int>[1, 2, 3],
          nextCursor: null,
          hasMore: false,
        )),
      );
      addTearDown(container.dispose);

      final PagedListState<int> state = await container.read(_provider.future);
      expect(state.items, <int>[1, 2, 3]);
      expect(state.hasMore, isFalse);
    });

    test('a first-page failure is carried in the state, not thrown', () async {
      // Regression: throwing it instead would settle the provider as
      // `AsyncLoading` with `hasError` set, and `AsyncValue.when` routes that
      // to `loading` — an infinite spinner where the user should see the
      // failure and a retry (requirement §41).
      final Failure failure = NetworkFailure.timeout(diagnostic: 't');
      final ProviderContainer container = _containerWith(
        (String query, Object? cursor) async => err(failure),
      );
      addTearDown(container.dispose);

      final PagedListState<int> state = await container.read(_provider.future);
      expect(state.failure, same(failure));
      expect(state.items, isEmpty);
      expect(state.hasMore, isFalse);
    });
  });

  group('setQuery', () {
    test('debounces rapid calls into one fetch for the final query', () async {
      final List<String> queriesReceived = <String>[];
      final ProviderContainer container = _containerWith((
        String query,
        Object? cursor,
      ) async {
        queriesReceived.add(query);
        return ok((items: const <int>[], nextCursor: null, hasMore: false));
      });
      addTearDown(container.dispose);
      await container.read(_provider.future); // initial build: query ''

      final _FakeController notifier = container.read(_provider.notifier);
      notifier.setQuery('a');
      notifier.setQuery('ab');
      notifier.setQuery('abc');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(queriesReceived, <String>['', 'abc']);
    });
  });

  group('loadMore', () {
    test('appends the next page and advances the cursor', () async {
      final ProviderContainer container = _containerWith((
        String query,
        Object? cursor,
      ) async {
        if (cursor == null) {
          return ok((items: const <int>[1, 2], nextCursor: 2, hasMore: true));
        }
        return ok((items: const <int>[3, 4], nextCursor: null, hasMore: false));
      });
      addTearDown(container.dispose);
      await container.read(_provider.future);

      final _FakeController notifier = container.read(_provider.notifier);
      await notifier.loadMore();

      final PagedListState<int> state = container.read(_provider).requireValue;
      expect(state.items, <int>[1, 2, 3, 4]);
      expect(state.hasMore, isFalse);
      expect(state.isLoadingMore, isFalse);
    });

    test('a load-more failure keeps existing items and is reported inline', () async {
      final Failure failure = NetworkFailure.unreachable(diagnostic: 't');
      bool firstCall = true;
      final ProviderContainer container = _containerWith((
        String query,
        Object? cursor,
      ) async {
        if (firstCall) {
          firstCall = false;
          return ok((items: const <int>[1, 2], nextCursor: 2, hasMore: true));
        }
        return err(failure);
      });
      addTearDown(container.dispose);
      await container.read(_provider.future);

      final _FakeController notifier = container.read(_provider.notifier);
      await notifier.loadMore();

      final PagedListState<int> state = container.read(_provider).requireValue;
      expect(state.items, <int>[1, 2]);
      expect(state.loadMoreFailure, failure);
      expect(state.isLoadingMore, isFalse);
    });

    test('is a no-op once hasMore is false', () async {
      int calls = 0;
      final ProviderContainer container = _containerWith((
        String query,
        Object? cursor,
      ) async {
        calls++;
        return ok((items: const <int>[1], nextCursor: null, hasMore: false));
      });
      addTearDown(container.dispose);
      await container.read(_provider.future);
      expect(calls, 1);

      await container.read(_provider.notifier).loadMore();
      expect(calls, 1, reason: 'hasMore was already false');
    });
  });

  group('stale responses', () {
    test('a response superseded by a newer query is dropped', () async {
      final Completer<Result<Page<int>>> pendingA =
          Completer<Result<Page<int>>>();
      final ProviderContainer container = _containerWith((
        String query,
        Object? cursor,
      ) async {
        if (query == 'a') {
          return pendingA.future;
        }
        if (query == 'b') {
          return ok((items: const <int>[99], nextCursor: null, hasMore: false));
        }
        return ok((items: const <int>[], nextCursor: null, hasMore: false));
      });
      addTearDown(container.dispose);
      await container.read(_provider.future); // initial build: query ''

      final _FakeController notifier = container.read(_provider.notifier);
      notifier.setQuery('a');
      // Let 'a' debounce fire; fetchPage('a') is now in flight, awaiting
      // `pendingA`.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      notifier.setQuery('b');
      // Let 'b' debounce fire and resolve (its response is immediate).
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(container.read(_provider).requireValue.items, <int>[99]);

      // Resolve the stale 'a' fetch now that 'b' has already won.
      pendingA.complete(
        ok((items: const <int>[1, 2, 3], nextCursor: null, hasMore: false)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        container.read(_provider).requireValue.items,
        <int>[99],
        reason: 'the stale response for "a" must not overwrite "b"',
      );
    });
  });

  group('refresh', () {
    test('re-fetches page one for the current query, discarding later pages', () async {
      int callCount = 0;
      final ProviderContainer container = _containerWith((
        String query,
        Object? cursor,
      ) async {
        callCount++;
        if (cursor == null) {
          return ok((items: const <int>[1, 2], nextCursor: 2, hasMore: true));
        }
        return ok((items: const <int>[3], nextCursor: null, hasMore: false));
      });
      addTearDown(container.dispose);
      await container.read(_provider.future);
      await container.read(_provider.notifier).loadMore();
      expect(container.read(_provider).requireValue.items, <int>[1, 2, 3]);

      await container.read(_provider.notifier).refresh();

      final PagedListState<int> state = container.read(_provider).requireValue;
      expect(state.items, <int>[1, 2]);
      expect(state.hasMore, isTrue);
      expect(callCount, 3);
    });
  });
}
