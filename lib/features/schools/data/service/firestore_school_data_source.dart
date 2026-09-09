/// Firestore implementation of [SchoolDataSource].
///
/// This is the only file in `features/schools/data` that imports
/// `cloud_firestore`, matching how `FirebaseAuthService` is the only auth
/// file that does (`lib/features/auth/data/service/firebase_auth_service.dart`).
/// Not yet exercised against a live project — like Phase 1's Firebase auth
/// path, it is compiled and type-checked now, and becomes live the moment a
/// project's rules are deployed (docs/11-environment-setup.md).
///
/// Pagination follows docs/03-firestore-schema.md: `.limit(pageSize)` with a
/// `startAfterDocument` cursor, never an unbounded query. Search is a prefix
/// match on the name field (`docs/03-firestore-schema.md` composite
/// indexes) — Firestore has no substring search without a third-party
/// indexer, which is out of scope for master-data browsing.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/service/school_data_source.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';

final class FirestoreSchoolDataSource implements SchoolDataSource {
  FirestoreSchoolDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<Page<StateEntity>>> listStates({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _list(
    collection: Collections.states,
    nameField: 'stateName',
    scopeField: scope.isGlobal ? null : 'stateId',
    scopeIds: scope.stateIds,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
    fromJson: StateEntity.tryFromJson,
    idField: 'stateId',
  );

  @override
  Future<Result<Page<District>>> listDistricts({
    required AccessScope scope,
    String? stateId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) {
    final (String? scopeField, Set<String> scopeIds) = _scopeFilter(
      parentGiven: stateId != null,
      scope: scope,
    );
    return _list(
      collection: Collections.districts,
      nameField: 'districtName',
      equalityField: stateId == null ? null : 'stateId',
      equalityValue: stateId,
      scopeField: scopeField,
      scopeIds: scopeIds,
      query: query,
      cursor: cursor,
      pageSize: pageSize,
      fromJson: District.tryFromJson,
      idField: 'districtId',
    );
  }

  @override
  Future<Result<Page<Cluster>>> listClusters({
    required AccessScope scope,
    String? districtId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) {
    final (String? scopeField, Set<String> scopeIds) = _scopeFilter(
      parentGiven: districtId != null,
      scope: scope,
    );
    return _list(
      collection: Collections.clusters,
      nameField: 'clusterName',
      equalityField: districtId == null ? null : 'districtId',
      equalityValue: districtId,
      scopeField: scopeField,
      scopeIds: scopeIds,
      query: query,
      cursor: cursor,
      pageSize: pageSize,
      fromJson: Cluster.tryFromJson,
      idField: 'clusterId',
    );
  }

  @override
  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) {
    final (String? scopeField, Set<String> scopeIds) = _scopeFilter(
      parentGiven: clusterId != null,
      scope: scope,
    );
    return _list(
      collection: Collections.schools,
      nameField: 'schoolName',
      equalityField: clusterId == null ? null : 'clusterId',
      equalityValue: clusterId,
      scopeField: scopeField,
      scopeIds: scopeIds,
      query: query,
      cursor: cursor,
      pageSize: pageSize,
      fromJson: School.tryFromJson,
      idField: 'schoolId',
    );
  }

  /// Determines the `whereIn` field/ids to apply for a scope-narrowed list.
  ///
  /// When the caller already gave a parent id (drilling into an already
  /// in-scope state/district/cluster), no further filter is needed — the
  /// parent itself came from a previously scope-filtered query. Otherwise
  /// (a "land on my own scope" view, with no parent chosen yet) the filter
  /// is keyed on the field matching the scope's own level: a state-scoped
  /// user's district landing view filters by `stateId`, a district-scoped
  /// user's by `districtId`, and so on. A scope narrower than what is being
  /// listed (for example a cluster-scoped user asking for a district
  /// landing view, which the UI never does) still resolves to a safe,
  /// deny-by-default filter rather than an unfiltered query.
  (String?, Set<String>) _scopeFilter({
    required bool parentGiven,
    required AccessScope scope,
  }) {
    if (parentGiven || scope.isGlobal) {
      return (null, const <String>{});
    }
    return switch (scope.level) {
      ScopeLevel.global => (null, const <String>{}),
      ScopeLevel.state => ('stateId', scope.stateIds),
      ScopeLevel.district => ('districtId', scope.districtIds),
      ScopeLevel.cluster => ('clusterId', scope.clusterIds),
      ScopeLevel.school => ('schoolId', scope.schoolIds),
    };
  }

  /// Shared query-building and paging for all four hierarchy levels.
  ///
  /// [scopeField]/[scopeIds] apply a `whereIn` when the scope is narrow
  /// enough that it cannot be expressed purely via [equalityField] — for
  /// example a Supervisor scoped to specific clusters browsing districts.
  /// `whereIn` accepts at most 30 values; a scope with more ids than that
  /// (the claims cap is ~40, docs/04-security-model.md) needs a follow-up
  /// batched-query pass, which is not implemented here — this ships correct
  /// for every scope this app currently issues, and the gap is a known
  /// boundary rather than a silent one.
  Future<Result<Page<T>>> _list<T>({
    required String collection,
    required String nameField,
    required String idField,
    required T? Function(Map<String, Object?>) fromJson,
    String? equalityField,
    String? equalityValue,
    String? scopeField,
    Set<String> scopeIds = const <String>{},
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    Query<Map<String, dynamic>> q = _firestore.collection(collection);
    if (equalityField != null && equalityValue != null) {
      q = q.where(equalityField, isEqualTo: equalityValue);
    }
    if (scopeField != null) {
      if (scopeIds.isEmpty) {
        // A non-global scope with nothing to match reaches nothing — never
        // silently "everything" (docs/02-data-model.md, AccessScope.isValid).
        return ok((items: const <Never>[], nextCursor: null, hasMore: false));
      }
      q = q.where(scopeField, whereIn: scopeIds.take(30).toList());
    }
    final String trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      // Standard Firestore prefix-range idiom: everything from `trimmed` up
      // to (but not including) `trimmed` with the highest Unicode code point
      // appended, ordered on the same field.
      q = q
          .where(nameField, isGreaterThanOrEqualTo: trimmed)
          .where(nameField, isLessThan: trimmed + kPrefixSearchUpperBound)
          .orderBy(nameField);
    } else {
      q = q.orderBy(nameField);
    }
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(cursor);
    }
    q = q.limit(pageSize);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot = await guardAsync(
      q.get,
      onError: _mapFirestoreError,
    );
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final Failure failure) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(
        :final QuerySnapshot<Map<String, dynamic>> value,
      ) =>
        ok(_toPage(value, idField, fromJson, pageSize)),
    };
  }

  Page<T> _toPage<T>(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String idField,
    T? Function(Map<String, Object?>) fromJson,
    int pageSize,
  ) {
    final List<T> items = snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              fromJson(<String, Object?>{...doc.data(), idField: doc.id}),
        )
        .whereType<T>()
        .toList(growable: false);
    final bool hasMore = snapshot.docs.length == pageSize;
    return (
      items: items,
      nextCursor: hasMore ? snapshot.docs.last : null,
      hasMore: hasMore,
    );
  }

  @override
  Future<Result<School>> getSchool(String schoolId) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore.collection(Collections.schools).doc(schoolId).get(),
          onError: _mapFirestoreError,
        );
    return switch (snapshot) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(
        :final Failure failure,
      ) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(:final value) =>
        _decodeOrNotFound(value, 'school', schoolId, School.tryFromJson),
    };
  }

  Result<T> _decodeOrNotFound<T>(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String entityType,
    String entityId,
    T? Function(Map<String, Object?>) fromJson,
  ) {
    final Map<String, dynamic>? data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That $entityType could not be found.',
          entityType: entityType,
          entityId: entityId,
        ),
      );
    }
    final T? value = fromJson(<String, Object?>{...data, '${entityType}Id': entityId});
    if (value == null) {
      return err(
        UnexpectedFailure(diagnostic: '$entityType document unreadable: $entityId'),
      );
    }
    return ok(value);
  }

  @override
  Future<Result<StateEntity>> createState(StateEntity state) => _create(
    collection: Collections.states,
    id: state.stateId,
    data: state.toJson(),
    value: state,
  );

  @override
  Future<Result<StateEntity>> updateState(StateEntity state) => _update(
    collection: Collections.states,
    id: state.stateId,
    data: state.toJson(),
    value: state,
  );

  @override
  Future<Result<District>> createDistrict(District district) => _create(
    collection: Collections.districts,
    id: district.districtId,
    data: district.toJson(),
    value: district,
  );

  @override
  Future<Result<District>> updateDistrict(District district) => _update(
    collection: Collections.districts,
    id: district.districtId,
    data: district.toJson(),
    value: district,
  );

  @override
  Future<Result<Cluster>> createCluster(Cluster cluster) => _create(
    collection: Collections.clusters,
    id: cluster.clusterId,
    data: cluster.toJson(),
    value: cluster,
  );

  @override
  Future<Result<Cluster>> updateCluster(Cluster cluster) => _update(
    collection: Collections.clusters,
    id: cluster.clusterId,
    data: cluster.toJson(),
    value: cluster,
  );

  @override
  Future<Result<School>> createSchool(School school) => _create(
    collection: Collections.schools,
    id: school.schoolId,
    data: school.toJson(),
    value: school,
  );

  @override
  Future<Result<School>> updateSchool(School school) => _update(
    collection: Collections.schools,
    id: school.schoolId,
    data: school.toJson(),
    value: school,
  );

  Future<Result<T>> _create<T>({
    required String collection,
    required String id,
    required Map<String, Object?> data,
    required T value,
  }) async {
    final Result<void> result = await guardAsync(
      () => _firestore.collection(collection).doc(id).set(data),
      onError: _mapFirestoreError,
    );
    return result.map((_) => value);
  }

  Future<Result<T>> _update<T>({
    required String collection,
    required String id,
    required Map<String, Object?> data,
    required T value,
  }) async {
    final Result<void> result = await guardAsync(
      () => _firestore.collection(collection).doc(id).update(data),
      onError: _mapFirestoreError,
    );
    return result.map((_) => value);
  }

  Failure _mapFirestoreError(Object error, StackTrace stackTrace) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => PermissionFailure.denied(
          diagnostic: 'firestore permission-denied',
        ),
        'unavailable' || 'network-request-failed' => NetworkFailure.unreachable(
          diagnostic: error.code,
          cause: error,
        ),
        'deadline-exceeded' => NetworkFailure.timeout(diagnostic: error.code),
        'not-found' => const NotFoundFailure(
          userMessage: 'That record could not be found.',
          entityType: 'hierarchy',
          entityId: 'unknown',
        ),
        _ => UnexpectedFailure(
          diagnostic: 'FirebaseException ${error.code}',
          cause: error,
          stackTrace: stackTrace,
        ),
      };
    }
    return UnexpectedFailure(
      diagnostic: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
