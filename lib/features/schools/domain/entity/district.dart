/// A district, nested under a state (docs/02-data-model.md §2).
library;

final class District {
  const District({
    required this.districtId,
    required this.districtName,
    required this.districtCode,
    required this.stateId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String districtId;
  final String districtName;
  final String districtCode;

  /// Ancestry. Denormalised so a scope check or an analytics query is a
  /// single indexed comparison (docs/03-firestore-schema.md).
  final String stateId;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'districtId': districtId,
    'districtName': districtName,
    'districtCode': districtCode,
    'stateId': stateId,
    'isActive': isActive,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static District? tryFromJson(Map<String, Object?> json) {
    final String? districtId = json['districtId'] as String?;
    final String? districtName = json['districtName'] as String?;
    final String? districtCode = json['districtCode'] as String?;
    final String? stateId = json['stateId'] as String?;
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    );
    if (districtId == null ||
        districtId.isEmpty ||
        districtName == null ||
        districtCode == null ||
        stateId == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return District(
      districtId: districtId,
      districtName: districtName,
      districtCode: districtCode,
      stateId: stateId,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  District copyWith({
    String? districtName,
    String? districtCode,
    bool? isActive,
    DateTime? updatedAt,
  }) => District(
    districtId: districtId,
    districtName: districtName ?? this.districtName,
    districtCode: districtCode ?? this.districtCode,
    stateId: stateId,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is District &&
      other.districtId == districtId &&
      other.districtName == districtName &&
      other.districtCode == districtCode &&
      other.stateId == stateId &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    districtId,
    districtName,
    districtCode,
    stateId,
    isActive,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'District($districtId, $districtName)';
}
