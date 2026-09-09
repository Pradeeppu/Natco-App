/// One school's assignment to an [Assessment] (docs/02-data-model.md section
/// 4).
///
/// Drives "OMRs Expected" in analytics and restricts which assessments a
/// teacher sees — the assessment *definition* itself carries no ancestry
/// (see `Assessment`'s doc comment), so this is the one place a school
/// actually connects to an assessment, and the one place that connection can
/// be scope-checked.
library;

import 'package:natco_app/features/assessments/domain/entity/assignment_status.dart';

DateTime? _parseUtc(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

final class AssessmentAssignment {
  const AssessmentAssignment({
    required this.assignmentId,
    required this.assessmentId,
    required this.schoolId,
    required this.grade,
    required this.sections,
    required this.assignedTeacherIds,
    required this.expectedStudentCount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
  });

  final String assignmentId;
  final String assessmentId;
  final String schoolId;
  final String grade;
  final List<String> sections;
  final List<String> assignedTeacherIds;
  final int expectedStudentCount;
  final DateTime? dueDate;
  final AssignmentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  AssessmentAssignment copyWith({
    List<String>? assignedTeacherIds,
    int? expectedStudentCount,
    DateTime? dueDate,
    AssignmentStatus? status,
    DateTime? updatedAt,
  }) => AssessmentAssignment(
    assignmentId: assignmentId,
    assessmentId: assessmentId,
    schoolId: schoolId,
    grade: grade,
    sections: sections,
    assignedTeacherIds: assignedTeacherIds ?? this.assignedTeacherIds,
    expectedStudentCount: expectedStudentCount ?? this.expectedStudentCount,
    dueDate: dueDate ?? this.dueDate,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'assignmentId': assignmentId,
    'assessmentId': assessmentId,
    'schoolId': schoolId,
    'grade': grade,
    'sections': sections,
    'assignedTeacherIds': assignedTeacherIds,
    'expectedStudentCount': expectedStudentCount,
    'dueDate': dueDate?.toUtc().toIso8601String(),
    'status': status.wireName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static AssessmentAssignment? tryFromJson(Map<String, Object?> json) {
    final String? assignmentId = json['assignmentId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? grade = json['grade'] as String?;
    final int? expectedStudentCount = (json['expectedStudentCount'] as num?)
        ?.toInt();
    final AssignmentStatus? status = AssignmentStatus.tryFromWireName(
      json['status'] as String?,
    );
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    if (assignmentId == null ||
        assessmentId == null ||
        schoolId == null ||
        grade == null ||
        expectedStudentCount == null ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return AssessmentAssignment(
      assignmentId: assignmentId,
      assessmentId: assessmentId,
      schoolId: schoolId,
      grade: grade,
      sections: (json['sections'] as List<Object?>? ?? const <Object?>[])
          .map((Object? o) => o.toString())
          .toList(growable: false),
      assignedTeacherIds:
          (json['assignedTeacherIds'] as List<Object?>? ?? const <Object?>[])
              .map((Object? o) => o.toString())
              .toList(growable: false),
      expectedStudentCount: expectedStudentCount,
      dueDate: _parseUtc(json['dueDate']),
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
