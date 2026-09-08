/// State, District and Cluster share an identical shape: a name, a code,
/// activity status and (below State) a parent id plus denormalised ancestry.
/// Modelling them as one class parameterised by [HierarchyLevel], rather than
/// three near-identical classes, is what lets the browsing UI and the create
/// form be written once and reused at every level (docs/02-data-model.md).
///
/// `School` is deliberately its own class, not a `GeoNode`: it carries enough
/// extra fields (address, grades, mediums) that folding it in here would make
/// every other level carry unused fields.
///
/// The JSON shape here is this app's own internal representation, with
/// generic field names (`id`, `name`, `code`) rather than the
/// level-prefixed names the documented Firestore schema uses
/// (`stateName`, `districtCode`, ...). Translating between the two is the
/// Firestore repository's job, not this entity's — that keeps this class
/// symmetric and trivial to round-trip, and keeps the wire-format detail in
/// the one place that actually talks to Firestore.
library;

import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';

final class GeoNode {
  const GeoNode({
    required this.id,
    required this.level,
    required this.name,
    required this.code,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.stateId,
    this.districtId,
  });

  final String id;
  final HierarchyLevel level;
  final String name;
  final String code;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The immediate parent's id. `null` for a State, which has none.
  final String? parentId;

  /// Denormalised ancestry, present from District downward, so a Cluster
  /// carries its own `stateId` without a lookup (docs/02-data-model.md,
  /// section 2).
  final String? stateId;

  /// Present from Cluster downward.
  final String? districtId;

  GeoNode copyWith({
    String? name,
    String? code,
    bool? isActive,
    DateTime? updatedAt,
  }) => GeoNode(
    id: id,
    level: level,
    name: name ?? this.name,
    code: code ?? this.code,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    parentId: parentId,
    stateId: stateId,
    districtId: districtId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'level': level.wireName,
    'name': name,
    'code': code,
    'isActive': isActive,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (parentId != null) 'parentId': parentId,
    if (stateId != null) 'stateId': stateId,
    if (districtId != null) 'districtId': districtId,
  };

  /// Reads a node from stored JSON. Returns `null` when the level is
  /// unrecognised or an identity field is missing.
  static GeoNode? tryFromJson(Map<String, Object?> json) {
    final String? id = json['id'] as String?;
    final String? name = json['name'] as String?;
    final String? code = json['code'] as String?;
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    final HierarchyLevel? level = _levelFromWireName(json['level'] as String?);
    if (id == null ||
        name == null ||
        code == null ||
        createdAt == null ||
        updatedAt == null ||
        level == null) {
      return null;
    }
    return GeoNode(
      id: id,
      level: level,
      name: name,
      code: code,
      isActive: json['isActive'] as bool? ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
      parentId: json['parentId'] as String?,
      stateId: json['stateId'] as String?,
      districtId: json['districtId'] as String?,
    );
  }

  static HierarchyLevel? _levelFromWireName(String? name) {
    for (final HierarchyLevel level in HierarchyLevel.values) {
      if (level.wireName == name) {
        return level;
      }
    }
    return null;
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  @override
  bool operator ==(Object other) =>
      other is GeoNode &&
      other.id == id &&
      other.level == level &&
      other.name == name &&
      other.code == code &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.parentId == parentId &&
      other.stateId == stateId &&
      other.districtId == districtId;

  @override
  int get hashCode => Object.hash(
    id,
    level,
    name,
    code,
    isActive,
    createdAt,
    updatedAt,
    parentId,
    stateId,
    districtId,
  );

  @override
  String toString() => 'GeoNode(${level.wireName}, $id, $name)';
}
