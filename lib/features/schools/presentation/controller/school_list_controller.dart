/// Paginated, searchable, scope-filtered school list.
///
/// Serves both the Schools screen's "search a school by name" shortcut
/// (`setClusterFilter(null)`, the default) and the hierarchy browser's final
/// drill-down level (`setClusterFilter(clusterId)`), because both are the
/// same list, just optionally narrowed to one cluster.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';

final class SchoolListController extends PagedListController<School> {
  String? _clusterId;

  /// The cluster currently narrowing this list, or `null` for a scope-wide
  /// search.
  String? get clusterFilter => _clusterId;

  /// Narrows (or clears) the list to one cluster and reloads from page one.
  void setClusterFilter(String? clusterId) {
    if (clusterId == _clusterId) {
      return;
    }
    _clusterId = clusterId;
    refresh();
  }

  @override
  Future<Result<Page<School>>> fetchPage({
    required String query,
    required Object? cursor,
  }) {
    final AccessScope scope = _scope();
    final SchoolHierarchyRepository repository = ref.read(
      schoolHierarchyRepositoryProvider,
    );
    return repository.listSchools(
      scope: scope,
      clusterId: _clusterId,
      query: query,
      cursor: cursor,
    );
  }

  /// The signed-in user's scope, or a scope that matches nothing if
  /// somehow called with no session — a route without `viewSchools` never
  /// reaches this controller, so this is a safety net, and it fails closed
  /// rather than defaulting to unrestricted access.
  AccessScope _scope() {
    final SessionState session = ref.read(sessionProvider);
    return session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
  }
}

final AsyncNotifierProvider<SchoolListController, PagedListState<School>>
schoolListControllerProvider =
    AsyncNotifierProvider<SchoolListController, PagedListState<School>>(
      SchoolListController.new,
    );
