/// In-memory [SchoolsRepository].
///
/// This is not a stub — it is how demo mode and every widget test browse and
/// manage the hierarchy with no Firebase project, and it is seeded with the
/// exact demo dataset requirement section 53 specifies (1 state, 2 districts,
/// 3 clusters, 5 schools).
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/schools_repository.dart';

final class InMemorySchoolsRepository implements SchoolsRepository {
  InMemorySchoolsRepository({
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _idGenerator = idGenerator,
       _clock = clock;

  final IdGenerator _idGenerator;
  final Clock _clock;

  final Map<String, GeoNode> _states = <String, GeoNode>{};
  final Map<String, GeoNode> _districts = <String, GeoNode>{};
  final Map<String, GeoNode> _clusters = <String, GeoNode>{};
  final Map<String, School> _schools = <String, School>{};

  /// Normalised (lowercased) school codes already in use, so a duplicate is
  /// rejected the same way a second student would be — with the existing
  /// record's identity, not a bare refusal (docs/02-data-model.md).
  final Set<String> _codesInUse = <String>{};

  // ---------------------------------------------------------------- reads

  @override
  Future<Result<Page<GeoNode>>> listStates({
    required AccessScope scope,
    String? query,
    PageRequest request = PageRequest.first,
  }) async => ok(
    _paginate(
      _filtered(
        _states.values,
        scope: scope,
        query: query,
        nameOf: (GeoNode n) => n.name,
        targetOf: (GeoNode n) => ScopeTarget(stateId: n.id),
      ),
      request,
      (GeoNode n) => n.id,
    ),
  );

  @override
  Future<Result<Page<GeoNode>>> listDistricts({
    required AccessScope scope,
    required String stateId,
    String? query,
    PageRequest request = PageRequest.first,
  }) async => ok(
    _paginate(
      _filtered(
        _districts.values.where((GeoNode d) => d.parentId == stateId),
        scope: scope,
        query: query,
        nameOf: (GeoNode n) => n.name,
        targetOf: (GeoNode n) =>
            ScopeTarget(stateId: n.stateId, districtId: n.id),
      ),
      request,
      (GeoNode n) => n.id,
    ),
  );

  @override
  Future<Result<Page<GeoNode>>> listClusters({
    required AccessScope scope,
    required String districtId,
    String? query,
    PageRequest request = PageRequest.first,
  }) async => ok(
    _paginate(
      _filtered(
        _clusters.values.where((GeoNode c) => c.parentId == districtId),
        scope: scope,
        query: query,
        nameOf: (GeoNode n) => n.name,
        targetOf: (GeoNode n) => ScopeTarget(
          stateId: n.stateId,
          districtId: n.districtId,
          clusterId: n.id,
        ),
      ),
      request,
      (GeoNode n) => n.id,
    ),
  );

  @override
  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String? query,
    PageRequest request = PageRequest.first,
  }) async {
    final Iterable<School> candidates = clusterId == null
        ? _schools.values
        : _schools.values.where((School s) => s.clusterId == clusterId);
    return ok(
      _paginate(
        _filtered(
          candidates,
          scope: scope,
          query: query,
          nameOf: (School s) => s.schoolName,
          targetOf: (School s) => ScopeTarget(
            stateId: s.stateId,
            districtId: s.districtId,
            clusterId: s.clusterId,
            schoolId: s.schoolId,
          ),
        ),
        request,
        (School s) => s.schoolId,
      ),
    );
  }

  @override
  Future<Result<School?>> getSchool(
    String schoolId, {
    required AccessScope scope,
  }) async {
    final School? school = _schools[schoolId];
    if (school == null) {
      return ok(null);
    }
    if (!scope.covers(
      ScopeTarget(
        stateId: school.stateId,
        districtId: school.districtId,
        clusterId: school.clusterId,
        schoolId: school.schoolId,
      ),
    )) {
      // Mirrors what a denied Firestore read looks like from the caller's
      // side: not "not found", but "you cannot reach this".
      return err(PermissionFailure.outOfScope());
    }
    return ok(school);
  }

  // --------------------------------------------------------------- writes

  @override
  Future<Result<GeoNode>> createState({
    required String name,
    required String code,
  }) async {
    final GeoNode node = GeoNode(
      id: _idGenerator.newId(),
      level: HierarchyLevel.state,
      name: name,
      code: code,
      isActive: true,
      createdAt: _clock.nowUtc(),
      updatedAt: _clock.nowUtc(),
    );
    _states[node.id] = node;
    return ok(node);
  }

  @override
  Future<Result<GeoNode>> createDistrict({
    required String name,
    required String code,
    required String stateId,
  }) async {
    if (!_states.containsKey(stateId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That state could not be found.',
          entityType: 'state',
          entityId: stateId,
        ),
      );
    }
    final GeoNode node = GeoNode(
      id: _idGenerator.newId(),
      level: HierarchyLevel.district,
      name: name,
      code: code,
      isActive: true,
      createdAt: _clock.nowUtc(),
      updatedAt: _clock.nowUtc(),
      parentId: stateId,
      stateId: stateId,
    );
    _districts[node.id] = node;
    return ok(node);
  }

  @override
  Future<Result<GeoNode>> createCluster({
    required String name,
    required String code,
    required String districtId,
  }) async {
    final GeoNode? district = _districts[districtId];
    if (district == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That district could not be found.',
          entityType: 'district',
          entityId: districtId,
        ),
      );
    }
    final GeoNode node = GeoNode(
      id: _idGenerator.newId(),
      level: HierarchyLevel.cluster,
      name: name,
      code: code,
      isActive: true,
      createdAt: _clock.nowUtc(),
      updatedAt: _clock.nowUtc(),
      parentId: districtId,
      stateId: district.stateId,
      districtId: districtId,
    );
    _clusters[node.id] = node;
    return ok(node);
  }

  @override
  Future<Result<School>> createSchool({
    required String schoolName,
    required String schoolCode,
    required String clusterId,
    required List<String> grades,
    required List<String> mediumsOfInstruction,
    String? address,
    String? pincode,
  }) async {
    final GeoNode? cluster = _clusters[clusterId];
    if (cluster == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That cluster could not be found.',
          entityType: 'cluster',
          entityId: clusterId,
        ),
      );
    }
    final String normalisedCode = schoolCode.trim().toLowerCase();
    if (_codesInUse.contains(normalisedCode)) {
      final School existing = _schools.values.firstWhere(
        (School s) => s.schoolCode.trim().toLowerCase() == normalisedCode,
      );
      return err(
        DuplicateFailure(
          userMessage:
              'School code "$schoolCode" is already used by '
              '"${existing.schoolName}".',
          entityType: 'school',
          entityId: existing.schoolId,
          details: <String, String>{
            'School': existing.schoolName,
            'Code': existing.schoolCode,
          },
        ),
      );
    }
    final DateTime now = _clock.nowUtc();
    final School school = School(
      schoolId: _idGenerator.newId(),
      schoolName: schoolName,
      schoolCode: schoolCode,
      clusterId: clusterId,
      districtId: cluster.districtId!,
      stateId: cluster.stateId!,
      address: address,
      pincode: pincode,
      grades: grades,
      mediumsOfInstruction: mediumsOfInstruction,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    _schools[school.schoolId] = school;
    _codesInUse.add(normalisedCode);
    return ok(school);
  }

  @override
  Future<Result<School>> updateSchool(School school) async {
    final School? existing = _schools[school.schoolId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: school.schoolId,
        ),
      );
    }
    // schoolId, schoolCode and ancestry are not accepted from the caller —
    // `School.copyWith` has no parameter for them, so identity cannot drift
    // through an update by construction, not by convention.
    final School updated = existing.copyWith(
      schoolName: school.schoolName,
      address: school.address,
      pincode: school.pincode,
      grades: school.grades,
      mediumsOfInstruction: school.mediumsOfInstruction,
      updatedAt: _clock.nowUtc(),
    );
    _schools[updated.schoolId] = updated;
    return ok(updated);
  }

  @override
  Future<Result<School>> setSchoolActive(String schoolId, bool isActive) async {
    final School? existing = _schools[schoolId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: schoolId,
        ),
      );
    }
    final School updated = existing.copyWith(
      isActive: isActive,
      updatedAt: _clock.nowUtc(),
    );
    _schools[schoolId] = updated;
    return ok(updated);
  }

  // ------------------------------------------------------------- seeding

  /// Inserts a fully-formed node without going through validation.
  ///
  /// Used only at startup by demo/seed data, which is known-good by
  /// construction. The public `create*` methods stay the only path an actual
  /// caller can reach, and they still validate.
  void seedState(GeoNode state) => _states[state.id] = state;

  void seedDistrict(GeoNode district) => _districts[district.id] = district;

  void seedCluster(GeoNode cluster) => _clusters[cluster.id] = cluster;

  void seedSchool(School school) {
    _schools[school.schoolId] = school;
    _codesInUse.add(school.schoolCode.trim().toLowerCase());
  }

  /// Direct, scope-free lookup for internal use by other repositories that
  /// need a school's ancestry (denormalising a new student's clusterId,
  /// districtId, stateId) — the equivalent of a Cloud Function reading with
  /// admin privileges rather than a user's own scope-restricted read.
  School? schoolByIdUnchecked(String schoolId) => _schools[schoolId];

  // -------------------------------------------------------------- helpers

  Iterable<T> _filtered<T>(
    Iterable<T> source, {
    required AccessScope scope,
    required ScopeTarget Function(T item) targetOf,
    required String Function(T item) nameOf,
    String? query,
  }) {
    final String? needle = (query == null || query.trim().isEmpty)
        ? null
        : query.trim().toLowerCase();
    return source.where((T item) {
      if (!scope.covers(targetOf(item))) {
        return false;
      }
      if (needle != null && !nameOf(item).toLowerCase().contains(needle)) {
        return false;
      }
      return true;
    });
  }

  Page<T> _paginate<T>(
    Iterable<T> filtered,
    PageRequest request,
    String Function(T item) idOf,
  ) {
    final List<T> sorted = filtered.toList()
      ..sort((T a, T b) => idOf(a).compareTo(idOf(b)));
    int startIndex = 0;
    if (request.cursor != null) {
      final int cursorIndex = sorted.indexWhere(
        (T item) => idOf(item) == request.cursor,
      );
      startIndex = cursorIndex == -1 ? 0 : cursorIndex + 1;
    }
    final List<T> pageItems = sorted
        .skip(startIndex)
        .take(request.limit)
        .toList(growable: false);
    final bool hasMore = startIndex + pageItems.length < sorted.length;
    return Page<T>(
      items: pageItems,
      nextCursor: hasMore ? idOf(pageItems.last) : null,
    );
  }
}
