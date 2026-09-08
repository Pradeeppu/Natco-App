/// Drives the hierarchy browser.
///
/// Two starting points, chosen once from the signed-in user's scope:
///
/// * **Global or state-scoped** users start at States and drill down through
///   Districts and Clusters to Schools. Every list call along the way is
///   correctly scope-filtered, because `AccessScope.covers` matches a state,
///   district or cluster target as soon as the scope's own level is at or
///   above it (docs/04-security-model.md).
/// * **Cluster- or school-scoped** users (a Supervisor, a teacher) start
///   directly at a flat, searchable Schools list. `SchoolsRepository.
///   listSchools` is the one list method that works correctly at every scope
///   level on its own, because a school's scope target carries its full
///   ancestry; `listDistricts`/`listClusters` need a concrete parent id to
///   list children of, which a cluster- or school-scoped user has no natural
///   way to supply without an extra lookup. Skipping straight to Schools
///   avoids presenting a drill-down whose upper levels would always come back
///   empty for these roles.
///
/// District-level scopes are not specially handled: no role in this system
/// currently uses one, and supporting it well would need a
/// "list my districts across states" repository method this phase does not
/// add. A district-scoped caller falls back to the flat Schools list, which
/// is correct but skips the drill-down — a limitation worth revisiting if a
/// role at that level is introduced.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/repository/schools_repository.dart';
import 'package:natco_app/features/schools/presentation/controller/schools_browser_state.dart';

final class SchoolsBrowserController extends Notifier<SchoolsBrowserState> {
  late SchoolsRepository _repository;
  late AccessScope _scope;

  @override
  SchoolsBrowserState build() {
    _repository = ref.watch(schoolsRepositoryProvider);
    _scope =
        ref.watch(sessionProvider).authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
    final BrowseLevel startLevel = switch (_scope.level) {
      ScopeLevel.global || ScopeLevel.state => BrowseLevel.states,
      ScopeLevel.district ||
      ScopeLevel.cluster ||
      ScopeLevel.school => BrowseLevel.schools,
    };
    final SchoolsBrowserState initial = SchoolsBrowserState.initial(startLevel);
    Future<void>.microtask(_loadFirstPage);
    return initial;
  }

  Future<void> _loadFirstPage() => _load(reset: true);

  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) {
      return;
    }
    await _load(reset: false);
  }

  Future<void> search(String query) async {
    state = state.copyWith(query: query);
    await _load(reset: true);
  }

  /// Drills from a [NodeRow] into its children — District list from a State
  /// row, Cluster list from a District row, School list from a Cluster row.
  Future<void> drillInto(NodeRow row) async {
    final BrowseLevel? next = switch (state.level) {
      BrowseLevel.states => BrowseLevel.districts,
      BrowseLevel.districts => BrowseLevel.clusters,
      BrowseLevel.clusters => BrowseLevel.schools,
      BrowseLevel.schools => null,
    };
    if (next == null) {
      return;
    }
    state = SchoolsBrowserState.initial(next).copyWith(
      breadcrumbs: <BreadcrumbStep>[
        ...state.breadcrumbs,
        BreadcrumbStep(id: row.id, label: row.title),
      ],
    );
    await _load(reset: true);
  }

  /// Returns to the breadcrumb at [index] (0 = the root the user started at).
  Future<void> goToBreadcrumb(int index) async {
    if (index >= state.breadcrumbs.length) {
      return;
    }
    final List<BreadcrumbStep> trimmed = state.breadcrumbs
        .sublist(0, index + 1)
        .toList(growable: false);
    final BrowseLevel level = _levelForDepth(trimmed.length);
    state = SchoolsBrowserState.initial(level).copyWith(breadcrumbs: trimmed);
    await _load(reset: true);
  }

  /// Returns to the root the user started at (States, or the flat Schools
  /// list for a narrowly-scoped user).
  Future<void> goToRoot() async {
    final BrowseLevel root = switch (_scope.level) {
      ScopeLevel.global || ScopeLevel.state => BrowseLevel.states,
      ScopeLevel.district ||
      ScopeLevel.cluster ||
      ScopeLevel.school => BrowseLevel.schools,
    };
    state = SchoolsBrowserState.initial(root);
    await _load(reset: true);
  }

  BrowseLevel _levelForDepth(int breadcrumbCount) => switch (breadcrumbCount) {
    0 => BrowseLevel.states,
    1 => BrowseLevel.districts,
    2 => BrowseLevel.clusters,
    _ => BrowseLevel.schools,
  };

  Future<void> _load({required bool reset}) async {
    state = reset
        ? state.copyWith(isLoading: true, clearFailure: true)
        : state.copyWith(isLoadingMore: true, clearFailure: true);

    final PageRequest request = PageRequest(
      cursor: reset ? null : state.nextCursor,
    );
    final String? query = state.query.isEmpty ? null : state.query;

    final Result<({List<HierarchyRow> rows, String? cursor})> result =
        switch (state.level) {
          BrowseLevel.states => _asRows(
            await _repository.listStates(
              scope: _scope,
              query: query,
              request: request,
            ),
            NodeRow.new,
          ),
          BrowseLevel.districts => _asRows(
            await _repository.listDistricts(
              scope: _scope,
              stateId: state.parentId!,
              query: query,
              request: request,
            ),
            NodeRow.new,
          ),
          BrowseLevel.clusters => _asRows(
            await _repository.listClusters(
              scope: _scope,
              districtId: state.parentId!,
              query: query,
              request: request,
            ),
            NodeRow.new,
          ),
          BrowseLevel.schools => _asRows(
            await _repository.listSchools(
              scope: _scope,
              clusterId: state.parentId,
              query: query,
              request: request,
            ),
            SchoolRow.new,
          ),
        };

    state = switch (result) {
      Success<({List<HierarchyRow> rows, String? cursor})>(:final value) =>
        state.copyWith(
          // On reset (a fresh search or a drill-down into a new level) the
          // previous page's rows must not survive into the new list — this
          // line used to unconditionally append to `state.rows`, which is
          // whatever the last search or level showed, producing duplicate
          // rows the moment a search actually narrowed the results.
          rows: <HierarchyRow>[
            if (!reset) ...state.rows,
            ...value.rows,
          ],
          nextCursor: value.cursor,
          clearNextCursor: value.cursor == null,
          isLoading: false,
          isLoadingMore: false,
        ),
      FailureResult<({List<HierarchyRow> rows, String? cursor})>(
        :final failure,
      ) =>
        state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          failure: failure,
        ),
    };
  }

  /// Converts a `Result<Page<T>>` into the `(rows, cursor)` shape every
  /// branch above needs, wrapping each item as a [HierarchyRow] with [toRow].
  Result<({List<HierarchyRow> rows, String? cursor})> _asRows<T>(
    Result<Page<T>> result,
    HierarchyRow Function(T item) toRow,
  ) => result.map(
    (Page<T> page) => (
      rows: page.items.map(toRow).toList(growable: false),
      cursor: page.nextCursor,
    ),
  );
}

/// The screen's controller.
final NotifierProvider<SchoolsBrowserController, SchoolsBrowserState>
schoolsBrowserProvider =
    NotifierProvider<SchoolsBrowserController, SchoolsBrowserState>(
      SchoolsBrowserController.new,
    );
