/// Small, single-page providers backing the State → District → Cluster
/// cascade (the hierarchy browser and `SchoolPicker`). Unlike Schools and
/// Students, these levels are expected to be small enough not to need
/// infinite scroll — but the query is still bounded
/// (docs/03-firestore-schema.md "Pagination": no screen loads an unbounded
/// collection), just at a generous single page size.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';

const int _kHierarchyPageSize = 200;

/// See `SchoolListController._scope` for why the fallback denies rather than
/// grants.
AccessScope _currentScope(Ref ref) {
  final SessionState session = ref.watch(sessionProvider);
  return session.authorization.user?.scope ??
      const AccessScope(level: ScopeLevel.school);
}

/// States the signed-in user may browse.
///
/// Yields a [Result] rather than throwing on failure: in this Riverpod
/// version a provider whose body throws settles as `AsyncLoading` with
/// `hasError` set, and `AsyncValue.when` routes that to its `loading`
/// branch — so a thrown failure renders as a spinner that never resolves
/// (requirement §41 forbids exactly that). Carrying the failure as data
/// keeps the error on screen with a retry.
final FutureProvider<Result<List<StateEntity>>> statesProvider =
    FutureProvider<Result<List<StateEntity>>>((Ref ref) async {
      final SchoolHierarchyRepository repo = ref.watch(
        schoolHierarchyRepositoryProvider,
      );
      final Result<Page<StateEntity>> result = await repo.listStates(
        scope: _currentScope(ref),
        pageSize: _kHierarchyPageSize,
      );
      return result.map((Page<StateEntity> p) => p.items);
    });

/// Districts under [stateId], or the caller's own scope when `null`.
///
/// The type is inferred rather than written out: Riverpod 3 does not export
/// its family provider types from `package:flutter_riverpod`, so naming one
/// here would not compile.
final districtsProvider =
    FutureProvider.family<Result<List<District>>, String?>((
      Ref ref,
      String? stateId,
    ) async {
      final SchoolHierarchyRepository repo = ref.watch(
        schoolHierarchyRepositoryProvider,
      );
      final Result<Page<District>> result = await repo.listDistricts(
        scope: _currentScope(ref),
        stateId: stateId,
        pageSize: _kHierarchyPageSize,
      );
      return result.map((Page<District> p) => p.items);
    });

/// Clusters under [districtId], or the caller's own scope when `null`.
final clustersProvider =
    FutureProvider.family<Result<List<Cluster>>, String?>((
      Ref ref,
      String? districtId,
    ) async {
      final SchoolHierarchyRepository repo = ref.watch(
        schoolHierarchyRepositoryProvider,
      );
      final Result<Page<Cluster>> result = await repo.listClusters(
        scope: _currentScope(ref),
        districtId: districtId,
        pageSize: _kHierarchyPageSize,
      );
      return result.map((Page<Cluster> p) => p.items);
    });
