/// Firestore implementation of [SchoolsRepository].
///
/// Field names on the wire are level-specific (`stateName`, `districtCode`,
/// ...) per docs/02-data-model.md, even though [GeoNode] uses one generic
/// shape in memory — translating between the two is this file's job (see
/// `GeoNode`'s own doc comment for why that split exists).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/data/remote/firestore_support.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/schools_repository.dart';

final class FirestoreSchoolsRepository implements SchoolsRepository {
  FirestoreSchoolsRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  // ---------------------------------------------------------------- reads

  @override
  Future<Result<Page<GeoNode>>> listStates({
    required AccessScope scope,
    String? query,
    PageRequest request = PageRequest.first,
  }) => _listNodes(
    collection: Collections.states,
    level: HierarchyLevel.state,
    idField: 'stateId',
    nameField: 'stateName',
    codeField: 'stateCode',
    scope: scope,
    // Every state within the caller's scope reaches here — the collection is
    // small (tens of rows nationally), so listing without a parent filter is
    // the whole point of "state" being the top level.
    parentFilter: null,
    query: query,
    request: request,
  );

  @override
  Future<Result<Page<GeoNode>>> listDistricts({
    required AccessScope scope,
    required String stateId,
    String? query,
    PageRequest request = PageRequest.first,
  }) => _listNodes(
    collection: Collections.districts,
    level: HierarchyLevel.district,
    idField: 'districtId',
    nameField: 'districtName',
    codeField: 'districtCode',
    scope: scope,
    parentFilter: ('stateId', stateId),
    query: query,
    request: request,
  );

  @override
  Future<Result<Page<GeoNode>>> listClusters({
    required AccessScope scope,
    required String districtId,
    String? query,
    PageRequest request = PageRequest.first,
  }) => _listNodes(
    collection: Collections.clusters,
    level: HierarchyLevel.cluster,
    idField: 'clusterId',
    nameField: 'clusterName',
    codeField: 'clusterCode',
    scope: scope,
    parentFilter: ('districtId', districtId),
    query: query,
    request: request,
  );

  @override
  Future<Result<Page<School>>> listSchools({
    required AccessScope scope,
    String? clusterId,
    String? query,
    PageRequest request = PageRequest.first,
  }) async {
    Query<Map<String, dynamic>> firestoreQuery = _firestore
        .collection(Collections.schools)
        .orderBy('schoolName')
        .orderBy(FieldPath.documentId);
    if (clusterId != null) {
      firestoreQuery = firestoreQuery.where('clusterId', isEqualTo: clusterId);
    }
    if (!scope.isGlobal) {
      final String? scopeField = switch (scope.level) {
        ScopeLevel.state => 'stateId',
        ScopeLevel.district => 'districtId',
        ScopeLevel.cluster => 'clusterId',
        ScopeLevel.school => null, // handled via a document-id filter below
        ScopeLevel.global => null,
      };
      if (scopeField != null) {
        firestoreQuery = firestoreQuery.where(
          scopeField,
          whereIn: scope.definingIds.toList(growable: false),
        );
      } else if (scope.level == ScopeLevel.school) {
        firestoreQuery = firestoreQuery.where(
          FieldPath.documentId,
          whereIn: scope.schoolIds.toList(growable: false),
        );
      }
    }
    if (query != null && query.trim().isNotEmpty) {
      // A prefix search: Firestore has no case-insensitive `contains`, and a
      // prefix range on the already-selected orderBy field needs no extra
      // index. The name search box's job is "jump to a school", not full-text
      // search, so a prefix match is the right amount of feature here.
      final String prefix = query.trim();
      firestoreQuery = firestoreQuery
          .where('schoolName', isGreaterThanOrEqualTo: prefix)
          .where('schoolName', isLessThan: '$prefix');
    }
    final FirestoreCursor? cursor = FirestoreCursor.tryDecode(request.cursor);
    if (cursor != null) {
      firestoreQuery = firestoreQuery.startAfter(<Object?>[
        cursor.orderValue,
        cursor.documentId,
      ]);
    }
    firestoreQuery = firestoreQuery.limit(request.limit);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(firestoreQuery.get, onError: mapFirestoreError);
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final failure) => err(
        failure,
      ),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok(
        _pageFromDocs<School>(
          value.docs,
          request.limit,
          orderValueOf: (Map<String, Object?> json) =>
              json['schoolName'] as String? ?? '',
          fromJson: School.tryFromJson,
        ),
      ),
    };
  }

  @override
  Future<Result<School?>> getSchool(
    String schoolId, {
    required AccessScope scope,
  }) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore.collection(Collections.schools).doc(schoolId).get(),
          onError: mapFirestoreError,
        );
    return switch (snapshot) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(:final failure) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(:final value) =>
        _mapSchoolDoc(value, scope),
    };
  }

  Result<School?> _mapSchoolDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    AccessScope scope,
  ) {
    final Map<String, dynamic>? data = doc.data();
    if (!doc.exists || data == null) {
      return ok(null);
    }
    final School? school = School.tryFromJson(
      firestoreDocToJson(data.cast<String, Object?>()),
    );
    if (school == null) {
      return err(
        const UnexpectedFailure(diagnostic: 'school document unreadable'),
      );
    }
    if (!scope.covers(
      ScopeTarget(
        stateId: school.stateId,
        districtId: school.districtId,
        clusterId: school.clusterId,
        schoolId: school.schoolId,
      ),
    )) {
      return err(PermissionFailure.outOfScope());
    }
    return ok(school);
  }

  // --------------------------------------------------------------- writes
  //
  // Creation runs server-side authorization via the security rules
  // (docs/04-security-model.md): `manageSchools`/`manageClusters`/etc. This
  // client sends the write and trusts the rule to accept or reject it, the
  // same posture `FirebaseAuthService` takes toward sign-in.

  @override
  Future<Result<GeoNode>> createState({
    required String name,
    required String code,
  }) => _createNode(
    collection: Collections.states,
    level: HierarchyLevel.state,
    idField: 'stateId',
    nameField: 'stateName',
    codeField: 'stateCode',
    name: name,
    code: code,
  );

  @override
  Future<Result<GeoNode>> createDistrict({
    required String name,
    required String code,
    required String stateId,
  }) => _createNode(
    collection: Collections.districts,
    level: HierarchyLevel.district,
    idField: 'districtId',
    nameField: 'districtName',
    codeField: 'districtCode',
    name: name,
    code: code,
    extraFields: <String, Object?>{'stateId': stateId},
  );

  @override
  Future<Result<GeoNode>> createCluster({
    required String name,
    required String code,
    required String districtId,
  }) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> district =
        await guardAsync(
          () => _firestore
              .collection(Collections.districts)
              .doc(districtId)
              .get(),
          onError: mapFirestoreError,
        );
    return switch (district) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(:final failure) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(:final value) =>
        await _createClusterUnderDistrict(name, code, districtId, value),
    };
  }

  Future<Result<GeoNode>> _createClusterUnderDistrict(
    String name,
    String code,
    String districtId,
    DocumentSnapshot<Map<String, dynamic>> districtDoc,
  ) async {
    final Map<String, dynamic>? data = districtDoc.data();
    final String? stateId = data == null ? null : data['stateId'] as String?;
    if (!districtDoc.exists || stateId == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That district could not be found.',
          entityType: 'district',
          entityId: districtId,
        ),
      );
    }
    return _createNode(
      collection: Collections.clusters,
      level: HierarchyLevel.cluster,
      idField: 'clusterId',
      nameField: 'clusterName',
      codeField: 'clusterCode',
      name: name,
      code: code,
      extraFields: <String, Object?>{
        'districtId': districtId,
        'stateId': stateId,
      },
    );
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
    final Result<DocumentSnapshot<Map<String, dynamic>>> cluster =
        await guardAsync(
          () =>
              _firestore.collection(Collections.clusters).doc(clusterId).get(),
          onError: mapFirestoreError,
        );
    return switch (cluster) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(:final failure) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(:final value) =>
        await _createSchoolUnderCluster(
          schoolName: schoolName,
          schoolCode: schoolCode,
          clusterId: clusterId,
          grades: grades,
          mediumsOfInstruction: mediumsOfInstruction,
          address: address,
          pincode: pincode,
          clusterDoc: value,
        ),
    };
  }

  Future<Result<School>> _createSchoolUnderCluster({
    required String schoolName,
    required String schoolCode,
    required String clusterId,
    required List<String> grades,
    required List<String> mediumsOfInstruction,
    required String? address,
    required String? pincode,
    required DocumentSnapshot<Map<String, dynamic>> clusterDoc,
  }) async {
    final Map<String, dynamic>? clusterData = clusterDoc.data();
    final String? districtId = clusterData == null
        ? null
        : clusterData['districtId'] as String?;
    final String? stateId = clusterData == null
        ? null
        : clusterData['stateId'] as String?;
    if (!clusterDoc.exists || districtId == null || stateId == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That cluster could not be found.',
          entityType: 'cluster',
          entityId: clusterId,
        ),
      );
    }

    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.schools)
        .doc();
    final DateTime now = DateTime.now().toUtc();
    final School school = School(
      schoolId: ref.id,
      schoolName: schoolName,
      schoolCode: schoolCode,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      address: address,
      pincode: pincode,
      grades: grades,
      mediumsOfInstruction: mediumsOfInstruction,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    // A uniqueness *check* here is advisory only — the security rules do not
    // enforce a unique schoolCode index (Firestore has none to offer), so the
    // authoritative guard is a Cloud Function reviewing this write, not this
    // client. This mirrors requirement section 34: server-side validation is
    // what counts. The set is still attempted with a create-only write so
    // Firestore itself rejects a same-id collision, which cannot happen here
    // since `ref.id` is freshly generated, but keeps the intent explicit.
    final Result<void> write = await guardAsync(
      () => ref.set(
        school.toJson()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp(),
      ),
      onError: mapFirestoreError,
    );
    return write.fold(onSuccess: (_) => ok(school), onFailure: err);
  }

  @override
  Future<Result<School>> updateSchool(School school) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.schools)
        .doc(school.schoolId);
    final Result<void> write = await guardAsync(
      () => ref.update(<String, Object?>{
        'schoolName': school.schoolName,
        'address': school.address,
        'pincode': school.pincode,
        'grades': school.grades,
        'mediumsOfInstruction': school.mediumsOfInstruction,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      onError: mapFirestoreError,
    );
    return write.fold(onSuccess: (_) => ok(school), onFailure: err);
  }

  @override
  Future<Result<School>> setSchoolActive(String schoolId, bool isActive) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.schools)
        .doc(schoolId);
    final Result<void> write = await guardAsync(
      () => ref.update(<String, Object?>{
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      onError: mapFirestoreError,
    );
    if (write.isFailure) {
      return err(write.failureOrNull!);
    }
    // A global scope here, not the caller's own: the update above already
    // succeeded under the security rules' authorization, so re-reading the
    // fresh document to return it is bookkeeping, not a fresh access
    // decision. Re-checking the caller's scope on this read could spuriously
    // fail for the legitimate case of deactivating a school at the edge of
    // one's own assignment.
    final Result<School?> reread = await getSchool(
      schoolId,
      scope: const AccessScope.global(),
    );
    return reread.flatMap(
      (School? school) => school == null
          ? err(
              NotFoundFailure(
                userMessage: 'That school could not be found.',
                entityType: 'school',
                entityId: schoolId,
              ),
            )
          : ok(school),
    );
  }

  // -------------------------------------------------------------- helpers

  Future<Result<Page<GeoNode>>> _listNodes({
    required String collection,
    required HierarchyLevel level,
    required String idField,
    required String nameField,
    required String codeField,
    required AccessScope scope,
    required (String field, String value)? parentFilter,
    String? query,
    PageRequest request = PageRequest.first,
  }) async {
    Query<Map<String, dynamic>> firestoreQuery = _firestore
        .collection(collection)
        .orderBy(nameField)
        .orderBy(FieldPath.documentId);
    if (parentFilter != null) {
      firestoreQuery = firestoreQuery.where(
        parentFilter.$1,
        isEqualTo: parentFilter.$2,
      );
    }
    if (query != null && query.trim().isNotEmpty) {
      final String prefix = query.trim();
      firestoreQuery = firestoreQuery
          .where(nameField, isGreaterThanOrEqualTo: prefix)
          .where(nameField, isLessThan: '$prefix');
    }
    final FirestoreCursor? cursor = FirestoreCursor.tryDecode(request.cursor);
    if (cursor != null) {
      firestoreQuery = firestoreQuery.startAfter(<Object?>[
        cursor.orderValue,
        cursor.documentId,
      ]);
    }
    firestoreQuery = firestoreQuery.limit(request.limit);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(firestoreQuery.get, onError: mapFirestoreError);
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final failure) => err(
        failure,
      ),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok(
        _pageFromDocs<GeoNode>(
          value.docs,
          request.limit,
          orderValueOf: (Map<String, Object?> json) =>
              json[nameField] as String? ?? '',
          fromJson: (Map<String, Object?> json) => _nodeFromLevelSpecificJson(
            json,
            level: level,
            idField: idField,
            nameField: nameField,
            codeField: codeField,
          ),
        ),
      ),
    };
  }

  Future<Result<GeoNode>> _createNode({
    required String collection,
    required HierarchyLevel level,
    required String idField,
    required String nameField,
    required String codeField,
    required String name,
    required String code,
    Map<String, Object?> extraFields = const <String, Object?>{},
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(collection)
        .doc();
    final DateTime now = DateTime.now().toUtc();
    final Result<void> write = await guardAsync(
      () => ref.set(<String, Object?>{
        idField: ref.id,
        nameField: name,
        codeField: code,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        ...extraFields,
      }),
      onError: mapFirestoreError,
    );
    return write.fold(
      onSuccess: (_) => ok(
        GeoNode(
          id: ref.id,
          level: level,
          name: name,
          code: code,
          isActive: true,
          createdAt: now,
          updatedAt: now,
          parentId: extraFields.values.isEmpty
              ? null
              : extraFields.values.last as String?,
          stateId: extraFields['stateId'] as String?,
          districtId: extraFields['districtId'] as String?,
        ),
      ),
      onFailure: err,
    );
  }

  /// Translates a level-specific document (`stateName`/`districtCode`/...)
  /// into [GeoNode]'s generic shape.
  GeoNode? _nodeFromLevelSpecificJson(
    Map<String, Object?> json, {
    required HierarchyLevel level,
    required String idField,
    required String nameField,
    required String codeField,
  }) => GeoNode.tryFromJson(<String, Object?>{
    'id': json[idField],
    'level': level.wireName,
    'name': json[nameField],
    'code': json[codeField],
    'isActive': json['isActive'],
    'createdAt': json['createdAt'],
    'updatedAt': json['updatedAt'],
    'parentId': json['stateId'] ?? json['districtId'],
    'stateId': json['stateId'],
    'districtId': json['districtId'],
  });

  /// Builds a [Page] from Firestore documents already limited to one page's
  /// worth (`request.limit` was applied to the query).
  Page<T> _pageFromDocs<T>(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int limit, {
    required String Function(Map<String, Object?> json) orderValueOf,
    required T? Function(Map<String, Object?> json) fromJson,
  }) {
    final List<T> items = <T>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final Map<String, Object?> json = firestoreDocToJson(
        doc.data().cast<String, Object?>(),
      );
      final T? item = fromJson(json);
      if (item != null) {
        items.add(item);
      }
    }
    // A full page suggests more may follow; fewer than requested means this
    // was the last one. This is the standard "did we get a full page" check,
    // which avoids a second round-trip just to learn there is nothing more.
    final bool hasMore = docs.length == limit && docs.isNotEmpty;
    String? nextCursor;
    if (hasMore) {
      final Map<String, Object?> lastJson = firestoreDocToJson(
        docs.last.data().cast<String, Object?>(),
      );
      nextCursor = FirestoreCursor(
        orderValue: orderValueOf(lastJson),
        documentId: docs.last.id,
      ).encode();
    }
    return Page<T>(items: items, nextCursor: nextCursor);
  }
}
