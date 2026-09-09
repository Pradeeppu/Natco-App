/// The geographic hierarchy: State → District → Cluster → School
/// (docs/02-data-model.md §2, requirement §10).
///
/// Every `list*` method takes the caller's own [AccessScope] and turns it
/// into the query filter itself — callers must always pass the signed-in
/// user's real scope, never an arbitrary one, because that is what makes the
/// result correct *by construction* rather than by a second filtering pass
/// that would break pagination (a page capped at 25 rows filtered
/// afterwards could return fewer than 25, or zero, even when more exist).
/// The Firestore implementation's queries are additionally bounded by
/// `firebase/firestore.rules`, so a patched client gets no further than the
/// rule allows regardless of what it asks for.
///
/// Mutations take `actorUserId`/`actorRole` because the repository has no
/// concept of "the current user" of its own — it is a long-lived singleton,
/// while the signed-in user can change across its lifetime — so the caller
/// (which already reads the session to build the [AccessScope] above)
/// supplies who is acting, for the audit entry.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';

abstract interface class SchoolHierarchyRepository {
  Future<Result<Page<StateEntity>>> listStates({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  /// Lists districts under [stateId] when given, otherwise the widest set
  /// [scope] allows — this serves both the drill-down and a state- or
  /// narrower-scoped user's landing view.
  Future<Result<Page<District>>> listDistricts({
    required AccessScope scope,
    String? stateId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  /// Lists clusters under [districtId] when given, otherwise the widest set
  /// [scope] allows.
  Future<Result<Page<Cluster>>> listClusters({
    required AccessScope scope,
    String? districtId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  /// Lists schools under [clusterId] when given, otherwise the widest set
  /// [scope] allows — this is both the hierarchy drill-down's last level and
  /// the flat, scope-wide "search a school by name" shortcut.
  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<School>> getSchool(String schoolId);

  Future<Result<StateEntity>> createState(
    StateEntity state, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<StateEntity>> updateState(
    StateEntity state, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<District>> createDistrict(
    District district, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<District>> updateDistrict(
    District district, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<Cluster>> createCluster(
    Cluster cluster, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<Cluster>> updateCluster(
    Cluster cluster, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<School>> createSchool(
    School school, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<School>> updateSchool(
    School school, {
    required String actorUserId,
    required String actorRole,
  });
}
