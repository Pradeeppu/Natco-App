/// Which schools sit which assessment (docs/02-data-model.md §4).
///
/// An assessment is not itself geographic — the same paper is sat across
/// several states — so this join is what makes "which assessments can this
/// Supervisor see?" answerable. It carries denormalised ancestry for the same
/// reason every other entity does: a scope check must be a set-membership
/// test, not an extra read.
library;

final class AssessmentAssignment {
  const AssessmentAssignment({
    required this.assignmentId,
    required this.assessmentId,
    required this.schoolId,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.grade,
    required this.assignedBy,
    required this.assignedAt,
    this.sections = const <String>[],
  });

  final String assignmentId;
  final String assessmentId;

  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;

  final String grade;

  /// Empty means every section of [grade] in this school.
  final List<String> sections;

  final String assignedBy;
  final DateTime assignedAt;

  bool coversSection(String section) =>
      sections.isEmpty || sections.contains(section);

  Map<String, Object?> toJson() => <String, Object?>{
    'assignmentId': assignmentId,
    'assessmentId': assessmentId,
    'schoolId': schoolId,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'grade': grade,
    'sections': sections,
    'assignedBy': assignedBy,
    'assignedAt': assignedAt.toUtc().toIso8601String(),
  };

  static AssessmentAssignment? tryFromJson(Map<String, Object?> json) {
    final String? assignmentId = json['assignmentId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? grade = json['grade'] as String?;
    final String? assignedBy = json['assignedBy'] as String?;
    final DateTime? assignedAt = DateTime.tryParse(
      json['assignedAt'] as String? ?? '',
    );
    if (assignmentId == null ||
        assessmentId == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        grade == null ||
        assignedBy == null ||
        assignedAt == null) {
      return null;
    }
    final Object? rawSections = json['sections'];
    return AssessmentAssignment(
      assignmentId: assignmentId,
      assessmentId: assessmentId,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      grade: grade,
      sections: rawSections is Iterable
          ? rawSections.whereType<String>().toList(growable: false)
          : const <String>[],
      assignedBy: assignedBy,
      assignedAt: assignedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AssessmentAssignment &&
      other.assignmentId == assignmentId &&
      other.assessmentId == assessmentId &&
      other.schoolId == schoolId &&
      other.clusterId == clusterId &&
      other.districtId == districtId &&
      other.stateId == stateId &&
      other.grade == grade &&
      other.sections.join(',') == sections.join(',') &&
      other.assignedBy == assignedBy &&
      other.assignedAt == assignedAt;

  @override
  int get hashCode => Object.hash(
    assignmentId,
    assessmentId,
    schoolId,
    clusterId,
    districtId,
    stateId,
    grade,
    sections.join(','),
    assignedBy,
    assignedAt,
  );

  @override
  String toString() =>
      'AssessmentAssignment($assessmentId -> $schoolId, grade $grade)';
}
