/// A school. Kept as its own class rather than folded into [GeoNode] because
/// it carries fields no other hierarchy level needs (docs/02-data-model.md).
library;

final class School {
  const School({
    required this.schoolId,
    required this.schoolName,
    required this.schoolCode,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.grades,
    required this.mediumsOfInstruction,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.address,
    this.pincode,
  });

  final String schoolId;
  final String schoolName;

  /// Unique. Enforced by a uniqueness guard in the repository, mirroring the
  /// `student_dedupe` pattern (docs/03-firestore-schema.md).
  final String schoolCode;

  final String clusterId;
  final String districtId;
  final String stateId;

  final String? address;
  final String? pincode;

  /// Grades actually taught here. Teachers and students may only be assigned
  /// to a grade in this list (requirement section 10: no free-typed values).
  final List<String> grades;
  final List<String> mediumsOfInstruction;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  School copyWith({
    String? schoolName,
    String? address,
    String? pincode,
    List<String>? grades,
    List<String>? mediumsOfInstruction,
    bool? isActive,
    DateTime? updatedAt,
  }) => School(
    schoolId: schoolId,
    schoolName: schoolName ?? this.schoolName,
    schoolCode: schoolCode,
    clusterId: clusterId,
    districtId: districtId,
    stateId: stateId,
    address: address ?? this.address,
    pincode: pincode ?? this.pincode,
    grades: grades ?? this.grades,
    mediumsOfInstruction: mediumsOfInstruction ?? this.mediumsOfInstruction,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schoolId': schoolId,
    'schoolName': schoolName,
    'schoolCode': schoolCode,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'address': address,
    'pincode': pincode,
    'grades': grades,
    'mediumsOfInstruction': mediumsOfInstruction,
    'isActive': isActive,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Reads a school from stored JSON. Returns `null` when required identity
  /// or ancestry fields are missing — a school with no ancestry cannot be
  /// scope-checked, and guessing a value would be a privilege escalation.
  static School? tryFromJson(Map<String, Object?> json) {
    final String? schoolId = json['schoolId'] as String?;
    final String? schoolName = json['schoolName'] as String?;
    final String? schoolCode = json['schoolCode'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    if (schoolId == null ||
        schoolName == null ||
        schoolCode == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return School(
      schoolId: schoolId,
      schoolName: schoolName,
      schoolCode: schoolCode,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      address: json['address'] as String?,
      pincode: json['pincode'] as String?,
      grades:
          (json['grades'] as List<Object?>?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      mediumsOfInstruction:
          (json['mediumsOfInstruction'] as List<Object?>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      isActive: json['isActive'] as bool? ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  @override
  bool operator ==(Object other) =>
      other is School &&
      other.schoolId == schoolId &&
      other.schoolName == schoolName &&
      other.schoolCode == schoolCode &&
      other.clusterId == clusterId &&
      other.districtId == districtId &&
      other.stateId == stateId &&
      other.address == address &&
      other.pincode == pincode &&
      _listEquals(other.grades, grades) &&
      _listEquals(other.mediumsOfInstruction, mediumsOfInstruction) &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    schoolId,
    schoolName,
    schoolCode,
    clusterId,
    districtId,
    stateId,
    address,
    pincode,
    Object.hashAll(grades),
    Object.hashAll(mediumsOfInstruction),
    isActive,
    createdAt,
    updatedAt,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'School($schoolId, $schoolName)';
}
