/// State for the hierarchy browser.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

/// The level currently displayed. Distinct from [HierarchyLevel]: that enum
/// describes what a node *is*, this describes what the *screen* shows, which
/// also needs a "flat schools" mode for narrowly-scoped users (see
/// `SchoolsBrowserController`'s doc comment for why).
enum BrowseLevel { states, districts, clusters, schools }

/// One row in the list: either a [GeoNode] (states/districts/clusters) or a
/// [School] — kept as a sealed pair rather than `Object` so the widget layer
/// pattern-matches exhaustively instead of casting.
sealed class HierarchyRow {
  const HierarchyRow();

  String get id;
  String get title;
}

final class NodeRow extends HierarchyRow {
  const NodeRow(this.node);

  final GeoNode node;

  @override
  String get id => node.id;

  @override
  String get title => node.name;
}

final class SchoolRow extends HierarchyRow {
  const SchoolRow(this.school);

  final School school;

  @override
  String get id => school.schoolId;

  @override
  String get title => school.schoolName;
}

/// One step in the breadcrumb trail: the id and label of a state/district/
/// cluster the user has drilled into.
final class BreadcrumbStep {
  const BreadcrumbStep({required this.id, required this.label});

  final String id;
  final String label;
}

final class SchoolsBrowserState {
  const SchoolsBrowserState({
    required this.level,
    required this.breadcrumbs,
    required this.query,
    required this.rows,
    required this.nextCursor,
    required this.isLoading,
    required this.isLoadingMore,
    this.failure,
  });

  const SchoolsBrowserState.initial(BrowseLevel startLevel)
    : level = startLevel,
      breadcrumbs = const <BreadcrumbStep>[],
      query = '',
      rows = const <HierarchyRow>[],
      nextCursor = null,
      isLoading = true,
      isLoadingMore = false,
      failure = null;

  final BrowseLevel level;

  /// The chain of states/districts/clusters drilled into to reach [level].
  /// Empty at the root, whatever the root level is for this user.
  final List<BreadcrumbStep> breadcrumbs;

  final String query;
  final List<HierarchyRow> rows;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final Failure? failure;

  bool get hasMore => nextCursor != null;

  /// The id of the immediate parent for the current level's list call, or
  /// `null` at the root.
  String? get parentId => breadcrumbs.isEmpty ? null : breadcrumbs.last.id;

  SchoolsBrowserState copyWith({
    BrowseLevel? level,
    List<BreadcrumbStep>? breadcrumbs,
    String? query,
    List<HierarchyRow>? rows,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoading,
    bool? isLoadingMore,
    Failure? failure,
    bool clearFailure = false,
  }) => SchoolsBrowserState(
    level: level ?? this.level,
    breadcrumbs: breadcrumbs ?? this.breadcrumbs,
    query: query ?? this.query,
    rows: rows ?? this.rows,
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}
