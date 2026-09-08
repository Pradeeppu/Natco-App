/// The geographic hierarchy, as seen by the presentation layer.
///
/// Every list method is scope-restricted by the caller's [AccessScope] and
/// paginated (requirement section 42) — there is no method here that can
/// return an unbounded collection.
library;

import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

abstract interface class SchoolsRepository {
  Future<Result<Page<GeoNode>>> listStates({
    required AccessScope scope,
    String? query,
    PageRequest request = PageRequest.first,
  });

  Future<Result<Page<GeoNode>>> listDistricts({
    required AccessScope scope,
    required String stateId,
    String? query,
    PageRequest request = PageRequest.first,
  });

  Future<Result<Page<GeoNode>>> listClusters({
    required AccessScope scope,
    required String districtId,
    String? query,
    PageRequest request = PageRequest.first,
  });

  /// Lists schools in [clusterId]. When [clusterId] is `null`, searches
  /// across the caller's whole scope by [query] instead of drilling down —
  /// this is what a state-level Viewer uses to jump straight to a school by
  /// name rather than descending through every level.
  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String? query,
    PageRequest request = PageRequest.first,
  });

  Future<Result<School?>> getSchool(
    String schoolId, {
    required AccessScope scope,
  });

  Future<Result<GeoNode>> createState({
    required String name,
    required String code,
  });
  Future<Result<GeoNode>> createDistrict({
    required String name,
    required String code,
    required String stateId,
  });
  Future<Result<GeoNode>> createCluster({
    required String name,
    required String code,
    required String districtId,
  });

  /// Creates a school. Fails with a [DuplicateFailure] when [schoolCode] is
  /// already in use (docs/02-data-model.md: schoolCode is unique).
  Future<Result<School>> createSchool({
    required String schoolName,
    required String schoolCode,
    required String clusterId,
    required List<String> grades,
    required List<String> mediumsOfInstruction,
    String? address,
    String? pincode,
  });

  Future<Result<School>> updateSchool(School school);

  /// Toggles a school active/inactive.
  ///
  /// Master data is deactivated, never hard-deleted: a school with historical
  /// students and results attached must stay resolvable for every record that
  /// references it, which a physical delete would break.
  Future<Result<School>> setSchoolActive(String schoolId, bool isActive);
}
