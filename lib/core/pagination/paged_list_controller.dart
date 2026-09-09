/// Base for a paginated, debounced-search, cursor-based list.
///
/// A screen like Schools or Students needs the same three behaviours —
/// infinite scroll, search-as-you-type, and "no screen loads an unbounded
/// collection" (requirement §42) — and this is written once here rather than
/// per feature. A concrete subclass only implements [fetchPage] against its
/// own repository; dependencies (the repository, the signed-in user's
/// `AccessScope`) are read via `ref.watch` inside [build], exactly like
/// `SessionController`
/// (`lib/features/auth/presentation/controller/session_controller.dart`) —
/// not injected through a constructor — so a test can override the
/// underlying provider and get the real controller wired to a fake backend.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';

/// How long typing pauses before a search actually fires a query.
const Duration kSearchDebounce = Duration(milliseconds: 350);

final class PagedListState<T> {
  const PagedListState({
    required this.items,
    this.query = '',
    this.cursor,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.failure,
    this.loadMoreFailure,
  });

  final List<T> items;
  final String query;
  final Object? cursor;
  final bool hasMore;
  final bool isLoadingMore;

  /// Set when the *first* page failed to load, so the screen can render
  /// `FailureView` with a retry.
  ///
  /// The failure is carried in the state rather than thrown out of [build]
  /// deliberately. In this Riverpod version a provider whose build throws
  /// settles as `AsyncLoading` with `hasError` set, and `AsyncValue.when`
  /// dispatches that to its `loading` branch — so a thrown failure would
  /// render as a spinner that never resolves, which is precisely the
  /// infinite loading screen requirement §41 forbids.
  final Failure? failure;

  /// Set only when a *subsequent* page failed to load. The first page's
  /// failure is carried by the enclosing `AsyncValue.error` instead — that is
  /// what `FailureView` already renders — so this one is shown inline at the
  /// bottom of an otherwise-populated list, and a transient failure on page 3
  /// does not blank pages 1 and 2.
  final Failure? loadMoreFailure;

  PagedListState<T> copyWith({
    List<T>? items,
    String? query,
    Object? cursor,
    bool clearCursor = false,
    bool? hasMore,
    bool? isLoadingMore,
    Failure? failure,
    bool clearFailure = false,
    Failure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
  }) => PagedListState<T>(
    items: items ?? this.items,
    query: query ?? this.query,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
    loadMoreFailure: clearLoadMoreFailure
        ? null
        : (loadMoreFailure ?? this.loadMoreFailure),
  );
}

abstract class PagedListController<T>
    extends AsyncNotifier<PagedListState<T>> {
  Timer? _debounceTimer;
  int _generation = 0;

  /// Fetches one page for [query], continuing from [cursor] (`null` for the
  /// first page). Implementations should apply the signed-in user's scope
  /// themselves — this class knows nothing about `AccessScope`.
  Future<Result<Page<T>>> fetchPage({
    required String query,
    required Object? cursor,
  });

  @override
  Future<PagedListState<T>> build() async {
    ref.onDispose(() => _debounceTimer?.cancel());
    final int generation = _generation;
    final PagedListState<T> firstPage = await _fetchFirstPage('');
    // A `refresh`/`setQuery` that ran concurrently and already resolved has
    // written a newer `state` directly; this build's own result must not
    // then overwrite it once Riverpod applies whatever this method returns.
    if (_generation != generation) {
      final PagedListState<T>? newer = state.value;
      if (newer != null) {
        return newer;
      }
    }
    return firstPage;
  }

  Future<PagedListState<T>> _fetchFirstPage(String query) async {
    final Result<Page<T>> result = await fetchPage(query: query, cursor: null);
    return switch (result) {
      Success<Page<T>>(:final Page<T> value) => PagedListState<T>(
        items: value.items,
        query: query,
        cursor: value.nextCursor,
        hasMore: value.hasMore,
      ),
      // Carried, not thrown — see [PagedListState.failure].
      FailureResult<Page<T>>(:final Failure failure) => PagedListState<T>(
        items: const <Never>[],
        query: query,
        hasMore: false,
        failure: failure,
      ),
    };
  }

  Future<void> _runQuery(String query, int generation) async {
    state = const AsyncValue.loading();
    final PagedListState<T> result = await _fetchFirstPage(query);
    if (generation != _generation) {
      return; // superseded by a newer keystroke or a refresh
    }
    state = AsyncValue<PagedListState<T>>.data(result);
  }

  /// Updates the search query, debounced so a fast typist does not fire one
  /// query per keystroke. This is fire-and-forget by design — a search box's
  /// `onChanged` does not await it — and a stale in-flight fetch is dropped
  /// by generation number when it resolves, since cancelling the underlying
  /// repository call once it has started is not something every backend can
  /// do.
  void setQuery(String query) {
    _debounceTimer?.cancel();
    final int generation = ++_generation;
    _debounceTimer = Timer(
      kSearchDebounce,
      () => unawaited(_runQuery(query, generation)),
    );
  }

  /// Appends the next page. A no-op while already loading more, or when the
  /// current page said there is nothing further.
  Future<void> loadMore() async {
    final PagedListState<T>? current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }
    final int generation = _generation;
    state = AsyncValue.data(
      current.copyWith(isLoadingMore: true, clearLoadMoreFailure: true),
    );
    final Result<Page<T>> result = await fetchPage(
      query: current.query,
      cursor: current.cursor,
    );
    if (generation != _generation) {
      return;
    }
    state = switch (result) {
      Success<Page<T>>(:final Page<T> value) => AsyncValue.data(
        current.copyWith(
          items: <T>[...current.items, ...value.items],
          cursor: value.nextCursor,
          clearCursor: value.nextCursor == null,
          hasMore: value.hasMore,
          isLoadingMore: false,
        ),
      ),
      FailureResult<Page<T>>(:final Failure failure) => AsyncValue.data(
        current.copyWith(isLoadingMore: false, loadMoreFailure: failure),
      ),
    };
  }

  /// Re-fetches the first page for the current query, discarding accumulated
  /// pages. Used for pull-to-refresh.
  Future<void> refresh() async {
    final String query = state.value?.query ?? '';
    final int generation = ++_generation;
    await _runQuery(query, generation);
  }
}
