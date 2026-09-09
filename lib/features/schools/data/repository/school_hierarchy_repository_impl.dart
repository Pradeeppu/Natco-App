/// The single [SchoolHierarchyRepository] implementation.
///
/// Composes a swappable [SchoolDataSource] with audit logging, so a mutation
/// is recorded exactly once regardless of whether the in-memory or Firestore
/// data source is wired in — mirroring `AuthRepositoryImpl`
/// (`lib/features/auth/data/repository/auth_repository_impl.dart`).
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/service/school_data_source.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';

final class SchoolHierarchyRepositoryImpl implements SchoolHierarchyRepository {
  SchoolHierarchyRepositoryImpl({
    required SchoolDataSource dataSource,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _dataSource = dataSource,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final SchoolDataSource _dataSource;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<Page<StateEntity>>> listStates({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listStates(
    scope: scope,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<Page<District>>> listDistricts({
    required AccessScope scope,
    String? stateId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listDistricts(
    scope: scope,
    stateId: stateId,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<Page<Cluster>>> listClusters({
    required AccessScope scope,
    String? districtId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listClusters(
    scope: scope,
    districtId: districtId,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listSchools(
    scope: scope,
    clusterId: clusterId,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<School>> getSchool(String schoolId) =>
      _dataSource.getSchool(schoolId);

  @override
  Future<Result<StateEntity>> createState(
    StateEntity state, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<StateEntity> result = await _dataSource.createState(state);
    if (result.isSuccess) {
      await _audit(
        AuditAction.stateCreated,
        entityType: 'state',
        entityId: state.stateId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{'stateCode': state.stateCode},
      );
    }
    return result;
  }

  @override
  Future<Result<StateEntity>> updateState(
    StateEntity state, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<StateEntity> result = await _dataSource.updateState(state);
    if (result.isSuccess) {
      await _audit(
        AuditAction.stateUpdated,
        entityType: 'state',
        entityId: state.stateId,
        actorUserId: actorUserId,
        actorRole: actorRole,
      );
    }
    return result;
  }

  @override
  Future<Result<District>> createDistrict(
    District district, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<District> result = await _dataSource.createDistrict(district);
    if (result.isSuccess) {
      await _audit(
        AuditAction.districtCreated,
        entityType: 'district',
        entityId: district.districtId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{'districtCode': district.districtCode},
      );
    }
    return result;
  }

  @override
  Future<Result<District>> updateDistrict(
    District district, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<District> result = await _dataSource.updateDistrict(district);
    if (result.isSuccess) {
      await _audit(
        AuditAction.districtUpdated,
        entityType: 'district',
        entityId: district.districtId,
        actorUserId: actorUserId,
        actorRole: actorRole,
      );
    }
    return result;
  }

  @override
  Future<Result<Cluster>> createCluster(
    Cluster cluster, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<Cluster> result = await _dataSource.createCluster(cluster);
    if (result.isSuccess) {
      await _audit(
        AuditAction.clusterCreated,
        entityType: 'cluster',
        entityId: cluster.clusterId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{'clusterCode': cluster.clusterCode},
      );
    }
    return result;
  }

  @override
  Future<Result<Cluster>> updateCluster(
    Cluster cluster, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<Cluster> result = await _dataSource.updateCluster(cluster);
    if (result.isSuccess) {
      await _audit(
        AuditAction.clusterUpdated,
        entityType: 'cluster',
        entityId: cluster.clusterId,
        actorUserId: actorUserId,
        actorRole: actorRole,
      );
    }
    return result;
  }

  @override
  Future<Result<School>> createSchool(
    School school, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<School> result = await _dataSource.createSchool(school);
    if (result.isSuccess) {
      await _audit(
        AuditAction.schoolCreated,
        entityType: 'school',
        entityId: school.schoolId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{'schoolCode': school.schoolCode},
      );
    }
    return result;
  }

  @override
  Future<Result<School>> updateSchool(
    School school, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<School> result = await _dataSource.updateSchool(school);
    if (result.isSuccess) {
      await _audit(
        AuditAction.schoolUpdated,
        entityType: 'school',
        entityId: school.schoolId,
        actorUserId: actorUserId,
        actorRole: actorRole,
      );
    }
    return result;
  }

  Future<void> _audit(
    AuditAction action, {
    required String entityType,
    required String entityId,
    required String actorUserId,
    required String actorRole,
    Map<String, Object?>? newValue,
  }) => _auditSink.record(
    AuditEvent(
      auditId: _idGenerator.newId(),
      userId: actorUserId,
      role: actorRole,
      action: action,
      entityType: entityType,
      entityId: entityId,
      timestamp: _clock.nowUtc(),
      deviceId: _deviceInfo.deviceId,
      appVersion: _deviceInfo.appVersion,
      newValue: newValue,
    ),
  );
}
