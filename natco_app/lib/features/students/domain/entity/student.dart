/// Student master data (requirement section 11).
///
/// A teacher never re-enters this data for each assessment — it is imported
/// or managed centrally, once, and referenced by [studentId] from every
/// session and submission after that.
library;

import 'package:natco_app/features/students/domain/entity/gender.dart';

final class Student {
  const Student({
    required this.studentId,
    required this.studentName,
    required this.gender,
    required this.grade,
    required this.section,
    required this.mediumOfInstruction,
    required this.language,
    required this.schoolId,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.activeStatus,
    required this.dedupeKey,
    required this.createdAt,
    required this.updatedAt,
    this.externalStudentCode,
    this.dateOfBirth,
    this.electiveSubject,
  });

  final String studentId;
  final String? externalStudentCode;
  final String studentName;
  final Gender gender;
  final DateTime? dateOfBirth;
  final String grade;
  final String section;
  final String mediumOfInstruction;
  final String language;
  final String? electiveSubject;

  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;

  final bool activeStatus;

  /// Deterministic hash of school + normalised name + grade + section + dob.
  /// Used as the uniqueness-guard document id, so a second write for the same
  /// child fails rather than creating a twin (requirement section 11).
  final String dedupeKey;

  final DateTime createdAt;
  final DateTime updatedAt;

  Student copyWith({
    String? studentName,
    Gender? gender,
    DateTime? dateOfBirth,
    String? grade,
    String? section,
    String? mediumOfInstruction,
    String? language,
    String? electiveSubject,
    bool? activeStatus,
    String? dedupeKey,
    DateTime? updatedAt,
  }) => Student(
    studentId: studentId,
    externalStudentCode: externalStudentCode,
    studentName: studentName ?? this.studentName,
    gender: gender ?? this.gender,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    grade: grade ?? this.grade,
    section: section ?? this.section,
    mediumOfInstruction: mediumOfInstruction ?? this.mediumOfInstruction,
    language: language ?? this.language,
    electiveSubject: electiveSubject ?? this.electiveSubject,
    schoolId: schoolId,
    clusterId: clusterId,
    districtId: districtId,
    stateId: stateId,
    activeStatus: activeStatus ?? this.activeStatus,
    dedupeKey: dedupeKey ?? this.dedupeKey,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'studentId': studentId,
    'externalStudentCode': externalStudentCode,
    'studentName': studentName,
    'gender': gender.wireName,
    'dateOfBirth': dateOfBirth?.toUtc().toIso8601String(),
    'grade': grade,
    'section': section,
    'mediumOfInstruction': mediumOfInstruction,
    'language': language,
    'electiveSubject': electiveSubject,
    'schoolId': schoolId,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'activeStatus': activeStatus,
    'dedupeKey': dedupeKey,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Reads a student from stored JSON. Returns `null` when identity or
  /// ancestry cannot be resolved — the same fail-closed posture as `School`
  /// and `AppUser`: a record this build cannot fully understand must not be
  /// partially trusted, because ancestry is what scope checks rely on.
  static Student? tryFromJson(Map<String, Object?> json) {
    final String? studentId = json['studentId'] as String?;
    final String? studentName = json['studentName'] as String?;
    final String? grade = json['grade'] as String?;
    final String? section = json['section'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? dedupeKey = json['dedupeKey'] as String?;
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    if (studentId == null ||
        studentName == null ||
        grade == null ||
        section == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        dedupeKey == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return Student(
      studentId: studentId,
      externalStudentCode: json['externalStudentCode'] as String?,
      studentName: studentName,
      gender: Gender.fromWireName(json['gender'] as String?),
      dateOfBirth: _parseUtc(json['dateOfBirth']),
      grade: grade,
      section: section,
      mediumOfInstruction: json['mediumOfInstruction'] as String? ?? '',
      language: json['language'] as String? ?? '',
      electiveSubject: json['electiveSubject'] as String?,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      activeStatus: json['activeStatus'] as bool? ?? true,
      dedupeKey: dedupeKey,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  @override
  bool operator ==(Object other) =>
      other is Student &&
      other.studentId == studentId &&
      other.externalStudentCode == externalStudentCode &&
      other.studentName == studentName &&
      other.gender == gender &&
      other.dateOfBirth == dateOfBirth &&
      other.grade == grade &&
      other.section == section &&
      other.mediumOfInstruction == mediumOfInstruction &&
      other.language == language &&
      other.electiveSubject == electiveSubject &&
      other.schoolId == schoolId &&
      other.clusterId == clusterId &&
      other.districtId == districtId &&
      other.stateId == stateId &&
      other.activeStatus == activeStatus &&
      other.dedupeKey == dedupeKey &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    studentId,
    externalStudentCode,
    studentName,
    gender,
    dateOfBirth,
    grade,
    Object.hash(section, mediumOfInstruction, language, electiveSubject),
    schoolId,
    Object.hash(clusterId, districtId, stateId),
    activeStatus,
    dedupeKey,
    Object.hash(createdAt, updatedAt),
  );

  @override
  String toString() => 'Student($studentId, $grade-$section)';
}
