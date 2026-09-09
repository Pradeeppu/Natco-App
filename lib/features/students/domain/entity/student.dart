/// Student master data (docs/02-data-model.md §3).
///
/// A teacher never re-enters this data per assessment (requirement §11); it
/// is managed centrally and referenced by id everywhere else.
library;

enum Gender {
  male('MALE'),
  female('FEMALE'),
  other('OTHER'),
  notSpecified('NOT_SPECIFIED');

  const Gender(this.wireName);

  final String wireName;

  static final Map<String, Gender> _byWireName = <String, Gender>{
    for (final Gender g in Gender.values) g.wireName: g,
  };

  static Gender tryFromWireName(String? name) =>
      name == null ? Gender.notSpecified : (_byWireName[name] ?? Gender.notSpecified);
}

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

  /// Ancestry, denormalised (docs/03-firestore-schema.md).
  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;

  final bool activeStatus;

  /// `sha256(schoolId|name|grade|section|dob)`, from
  /// `IdGenerator.dedupeKey()`. Immutable after creation — both the
  /// Firestore rule and the repository layer refuse to change it, because a
  /// dedupe key that can be rewritten guards nothing (docs/04-security-model.md).
  final String dedupeKey;

  final DateTime createdAt;
  final DateTime updatedAt;

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

  static Student? tryFromJson(Map<String, Object?> json) {
    final String? studentId = json['studentId'] as String?;
    final String? studentName = json['studentName'] as String?;
    final String? grade = json['grade'] as String?;
    final String? section = json['section'] as String?;
    final String? mediumOfInstruction = json['mediumOfInstruction'] as String?;
    final String? language = json['language'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? dedupeKey = json['dedupeKey'] as String?;
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    );
    if (studentId == null ||
        studentId.isEmpty ||
        studentName == null ||
        grade == null ||
        section == null ||
        mediumOfInstruction == null ||
        language == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        dedupeKey == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    final Object? rawDob = json['dateOfBirth'];
    return Student(
      studentId: studentId,
      externalStudentCode: json['externalStudentCode'] as String?,
      studentName: studentName,
      gender: Gender.tryFromWireName(json['gender'] as String?),
      dateOfBirth: rawDob is String ? DateTime.tryParse(rawDob) : null,
      grade: grade,
      section: section,
      mediumOfInstruction: mediumOfInstruction,
      language: language,
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

  /// Note: intentionally has no way to change [schoolId], [studentName],
  /// [grade], [section] or [dateOfBirth] without also being told the new
  /// [dedupeKey] — those fields are exactly what the key is derived from, and
  /// a caller that changes one without recomputing the other has a bug
  /// (docs/04-security-model.md: the key is immutable, not the fields it
  /// covers, so a genuine correction re-derives it explicitly).
  Student copyWith({
    String? externalStudentCode,
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
    externalStudentCode: externalStudentCode ?? this.externalStudentCode,
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
    section,
    mediumOfInstruction,
    Object.hash(language, electiveSubject, schoolId, clusterId),
    districtId,
    stateId,
    activeStatus,
    dedupeKey,
    Object.hash(createdAt, updatedAt),
  );

  /// Deliberately omits [studentName] and [dateOfBirth]: this string can end
  /// up in logs, and student personal data must not (requirement §35).
  @override
  String toString() => 'Student($studentId, $schoolId, $grade-$section)';
}
