/// A state: the top of the geographic hierarchy.
///
/// Named `StateEntity` rather than `State` because `State` collides with
/// Flutter's own widget state class in every file that imports
/// `package:flutter/material.dart` (docs/02-data-model.md §2).
library;

final class StateEntity {
  const StateEntity({
    required this.stateId,
    required this.stateName,
    required this.stateCode,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String stateId;
  final String stateName;
  final String stateCode;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'stateId': stateId,
    'stateName': stateName,
    'stateCode': stateCode,
    'isActive': isActive,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static StateEntity? tryFromJson(Map<String, Object?> json) {
    final String? stateId = json['stateId'] as String?;
    final String? stateName = json['stateName'] as String?;
    final String? stateCode = json['stateCode'] as String?;
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    );
    if (stateId == null ||
        stateId.isEmpty ||
        stateName == null ||
        stateCode == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return StateEntity(
      stateId: stateId,
      stateName: stateName,
      stateCode: stateCode,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  StateEntity copyWith({
    String? stateName,
    String? stateCode,
    bool? isActive,
    DateTime? updatedAt,
  }) => StateEntity(
    stateId: stateId,
    stateName: stateName ?? this.stateName,
    stateCode: stateCode ?? this.stateCode,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is StateEntity &&
      other.stateId == stateId &&
      other.stateName == stateName &&
      other.stateCode == stateCode &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(stateId, stateName, stateCode, isActive, createdAt, updatedAt);

  @override
  String toString() => 'StateEntity($stateId, $stateName)';
}
