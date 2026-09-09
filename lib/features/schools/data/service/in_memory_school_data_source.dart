/// In-memory [SchoolDataSource].
///
/// Backs demo mode and tests, exactly as `InMemoryAuthService` backs the
/// auth feature — not a stub, but how the whole hierarchy browser runs with
/// no Firebase project.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/service/school_data_source.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';

final class InMemorySchoolDataSource implements SchoolDataSource {
  InMemorySchoolDataSource({
    List<StateEntity> states = const <StateEntity>[],
    List<District> districts = const <District>[],
    List<Cluster> clusters = const <Cluster>[],
    List<School> schools = const <School>[],
  }) : _states = <String, StateEntity>{
         for (final StateEntity s in states) s.stateId: s,
       },
       _districts = <String, District>{
         for (final District d in districts) d.districtId: d,
       },
       _clusters = <String, Cluster>{
         for (final Cluster c in clusters) c.clusterId: c,
       },
       _schools = <String, School>{
         for (final School s in schools) s.schoolId: s,
       };

  final Map<String, StateEntity> _states;
  final Map<String, District> _districts;
  final Map<String, Cluster> _clusters;
  final Map<String, School> _schools;

  @override
  Future<Result<Page<StateEntity>>> listStates({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final List<StateEntity> matching =
        _states.values
            .where(
              (StateEntity s) => scope.covers(ScopeTarget(stateId: s.stateId)),
            )
            .where((StateEntity s) => _matches(query, <String>[
              s.stateName,
              s.stateCode,
            ]))
            .toList()
          ..sort((StateEntity a, StateEntity b) => a.stateName.compareTo(b.stateName));
    return ok(_page(matching, cursor, pageSize));
  }

  @override
  Future<Result<Page<District>>> listDistricts({
    required AccessScope scope,
    String? stateId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final List<District> matching =
        _districts.values
            .where((District d) => stateId == null || d.stateId == stateId)
            .where(
              (District d) => scope.covers(
                ScopeTarget(stateId: d.stateId, districtId: d.districtId),
              ),
            )
            .where((District d) => _matches(query, <String>[
              d.districtName,
              d.districtCode,
            ]))
            .toList()
          ..sort((District a, District b) => a.districtName.compareTo(b.districtName));
    return ok(_page(matching, cursor, pageSize));
  }

  @override
  Future<Result<Page<Cluster>>> listClusters({
    required AccessScope scope,
    String? districtId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final List<Cluster> matching =
        _clusters.values
            .where((Cluster c) => districtId == null || c.districtId == districtId)
            .where(
              (Cluster c) => scope.covers(
                ScopeTarget(
                  stateId: c.stateId,
                  districtId: c.districtId,
                  clusterId: c.clusterId,
                ),
              ),
            )
            .where((Cluster c) => _matches(query, <String>[
              c.clusterName,
              c.clusterCode,
            ]))
            .toList()
          ..sort((Cluster a, Cluster b) => a.clusterName.compareTo(b.clusterName));
    return ok(_page(matching, cursor, pageSize));
  }

  @override
  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final List<School> matching =
        _schools.values
            .where((School s) => clusterId == null || s.clusterId == clusterId)
            .where(
              (School s) => scope.covers(
                ScopeTarget(
                  stateId: s.stateId,
                  districtId: s.districtId,
                  clusterId: s.clusterId,
                  schoolId: s.schoolId,
                ),
              ),
            )
            .where((School s) => _matches(query, <String>[
              s.schoolName,
              s.schoolCode,
            ]))
            .toList()
          ..sort((School a, School b) => a.schoolName.compareTo(b.schoolName));
    return ok(_page(matching, cursor, pageSize));
  }

  @override
  Future<Result<School>> getSchool(String schoolId) async {
    final School? school = _schools[schoolId];
    if (school == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: schoolId,
        ),
      );
    }
    return ok(school);
  }

  @override
  Future<Result<StateEntity>> createState(StateEntity state) async {
    if (_states.containsKey(state.stateId)) {
      return err(
        DuplicateFailure(
          userMessage: 'A state with this code already exists.',
          entityType: 'state',
          entityId: state.stateId,
        ),
      );
    }
    _states[state.stateId] = state;
    return ok(state);
  }

  @override
  Future<Result<StateEntity>> updateState(StateEntity state) async {
    if (!_states.containsKey(state.stateId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That state could not be found.',
          entityType: 'state',
          entityId: state.stateId,
        ),
      );
    }
    _states[state.stateId] = state;
    return ok(state);
  }

  @override
  Future<Result<District>> createDistrict(District district) async {
    if (_districts.containsKey(district.districtId)) {
      return err(
        DuplicateFailure(
          userMessage: 'A district with this code already exists.',
          entityType: 'district',
          entityId: district.districtId,
        ),
      );
    }
    _districts[district.districtId] = district;
    return ok(district);
  }

  @override
  Future<Result<District>> updateDistrict(District district) async {
    if (!_districts.containsKey(district.districtId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That district could not be found.',
          entityType: 'district',
          entityId: district.districtId,
        ),
      );
    }
    _districts[district.districtId] = district;
    return ok(district);
  }

  @override
  Future<Result<Cluster>> createCluster(Cluster cluster) async {
    if (_clusters.containsKey(cluster.clusterId)) {
      return err(
        DuplicateFailure(
          userMessage: 'A cluster with this code already exists.',
          entityType: 'cluster',
          entityId: cluster.clusterId,
        ),
      );
    }
    _clusters[cluster.clusterId] = cluster;
    return ok(cluster);
  }

  @override
  Future<Result<Cluster>> updateCluster(Cluster cluster) async {
    if (!_clusters.containsKey(cluster.clusterId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That cluster could not be found.',
          entityType: 'cluster',
          entityId: cluster.clusterId,
        ),
      );
    }
    _clusters[cluster.clusterId] = cluster;
    return ok(cluster);
  }

  @override
  Future<Result<School>> createSchool(School school) async {
    final bool codeTaken = _schools.values.any(
      (School s) =>
          s.schoolId != school.schoolId &&
          s.schoolCode.toLowerCase() == school.schoolCode.toLowerCase(),
    );
    if (codeTaken) {
      return err(
        DuplicateFailure(
          userMessage: 'A school with this code already exists.',
          entityType: 'school',
          entityId: school.schoolId,
          details: <String, String>{'schoolCode': school.schoolCode},
        ),
      );
    }
    _schools[school.schoolId] = school;
    return ok(school);
  }

  @override
  Future<Result<School>> updateSchool(School school) async {
    if (!_schools.containsKey(school.schoolId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: school.schoolId,
        ),
      );
    }
    _schools[school.schoolId] = school;
    return ok(school);
  }

  static bool _matches(String query, List<String> fields) {
    if (query.trim().isEmpty) {
      return true;
    }
    final String needle = query.trim().toLowerCase();
    return fields.any((String f) => f.toLowerCase().contains(needle));
  }

  static Page<T> _page<T>(List<T> matching, Object? cursor, int pageSize) {
    final int offset = cursor is int ? cursor : 0;
    final int end = (offset + pageSize).clamp(0, matching.length);
    final List<T> items = offset >= matching.length
        ? const <Never>[]
        : matching.sublist(offset, end);
    final bool hasMore = end < matching.length;
    return (items: items, nextCursor: hasMore ? end : null, hasMore: hasMore);
  }
}
