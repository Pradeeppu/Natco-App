/// A cluster, nested under a district (docs/02-data-model.md §2).
///
/// This is the level a Supervisor is most often scoped to
/// (docs/04-security-model.md §31).
library;

final class Cluster {
  const Cluster({
    required this.clusterId,
    required this.clusterName,
    required this.clusterCode,
    required this.districtId,
    required this.stateId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String clusterId;
  final String clusterName;
  final String clusterCode;

  /// Ancestry, denormalised (docs/03-firestore-schema.md).
  final String districtId;
  final String stateId;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'clusterId': clusterId,
    'clusterName': clusterName,
    'clusterCode': clusterCode,
    'districtId': districtId,
    'stateId': stateId,
    'isActive': isActive,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static Cluster? tryFromJson(Map<String, Object?> json) {
    final String? clusterId = json['clusterId'] as String?;
    final String? clusterName = json['clusterName'] as String?;
    final String? clusterCode = json['clusterCode'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    );
    if (clusterId == null ||
        clusterId.isEmpty ||
        clusterName == null ||
        clusterCode == null ||
        districtId == null ||
        stateId == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return Cluster(
      clusterId: clusterId,
      clusterName: clusterName,
      clusterCode: clusterCode,
      districtId: districtId,
      stateId: stateId,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Cluster copyWith({
    String? clusterName,
    String? clusterCode,
    bool? isActive,
    DateTime? updatedAt,
  }) => Cluster(
    clusterId: clusterId,
    clusterName: clusterName ?? this.clusterName,
    clusterCode: clusterCode ?? this.clusterCode,
    districtId: districtId,
    stateId: stateId,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Cluster &&
      other.clusterId == clusterId &&
      other.clusterName == clusterName &&
      other.clusterCode == clusterCode &&
      other.districtId == districtId &&
      other.stateId == stateId &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    clusterId,
    clusterName,
    clusterCode,
    districtId,
    stateId,
    isActive,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Cluster($clusterId, $clusterName)';
}
