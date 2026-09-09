/// Raw hierarchy CRUD and paged queries, with no audit logging — the
/// swappable half of school data access. `SchoolHierarchyRepositoryImpl`
/// composes this with an `AuditSink` so every mutation is recorded exactly
/// once regardless of which implementation is wired in, mirroring the
/// `AuthService`/`AuthRepositoryImpl` split
/// (`lib/features/auth/data/service/auth_service.dart`).
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';

abstract interface class SchoolDataSource {
  Future<Result<Page<StateEntity>>> listStates({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<Page<District>>> listDistricts({
    required AccessScope scope,
    String? stateId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<Page<Cluster>>> listClusters({
    required AccessScope scope,
    String? districtId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<School>> getSchool(String schoolId);

  Future<Result<StateEntity>> createState(StateEntity state);
  Future<Result<StateEntity>> updateState(StateEntity state);
  Future<Result<District>> createDistrict(District district);
  Future<Result<District>> updateDistrict(District district);
  Future<Result<Cluster>> createCluster(Cluster cluster);
  Future<Result<Cluster>> updateCluster(Cluster cluster);
  Future<Result<School>> createSchool(School school);
  Future<Result<School>> updateSchool(School school);
}
