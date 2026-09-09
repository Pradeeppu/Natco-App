/// One teacher's live run of an assessment for one grade-section
/// (docs/02-data-model.md section 5).
///
/// A session is the unit "offline-first" is built around: everything it
/// needs — the assessment, its questions, the published answer key, the
/// student roster — is pre-downloaded before it starts, and every write
/// against it is a local commit (docs/06-offline-sync-strategy.md §1). This
/// entity is what a device still has, complete and correct, after being
/// killed mid-session.
library;

import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';

final class AssessmentSession {
  const AssessmentSession({
    required this.sessionId,
    required this.assessmentId,
    required this.schoolId,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.grade,
    required this.section,
    required this.subject,
    required this.academicYear,
    required this.assessmentDate,
    required this.teacherUserId,
    required this.studentIds,
    required this.expectedStudentCount,
    required this.status,
    required this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.endedAt,
  });

  final String sessionId;
  final String assessmentId;
  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;
  final String grade;
  final String section;
  final String subject;
  final String academicYear;
  final DateTime assessmentDate;
  final String teacherUserId;

  /// The roster this session was started against — resolved once, at start,
  /// from the pre-downloaded student list. A student added to the school
  /// afterwards does not retroactively join a session already in progress.
  final List<String> studentIds;

  final int expectedStudentCount;

  final DateTime? startedAt;
  final DateTime? endedAt;

  final SessionStatus status;
  final String deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  AssessmentSession copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    SessionStatus? status,
    DateTime? updatedAt,
  }) => AssessmentSession(
    sessionId: sessionId,
    assessmentId: assessmentId,
    schoolId: schoolId,
    clusterId: clusterId,
    districtId: districtId,
    stateId: stateId,
    grade: grade,
    section: section,
    subject: subject,
    academicYear: academicYear,
    assessmentDate: assessmentDate,
    teacherUserId: teacherUserId,
    studentIds: studentIds,
    expectedStudentCount: expectedStudentCount,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    status: status ?? this.status,
    deviceId: deviceId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'assessmentId': assessmentId,
    'schoolId': schoolId,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'grade': grade,
    'section': section,
    'subject': subject,
    'academicYear': academicYear,
    'assessmentDate': assessmentDate.toUtc().toIso8601String(),
    'teacherUserId': teacherUserId,
    'studentIds': studentIds,
    'expectedStudentCount': expectedStudentCount,
    'startedAt': startedAt?.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'status': status.wireName,
    'deviceId': deviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Reads a session from stored JSON. Returns `null` when identity, ancestry
  /// or the status cannot be resolved — a record this build cannot fully
  /// understand must not be partially trusted, the same fail-closed posture
  /// as `School.tryFromJson` and `Student.tryFromJson`.
  static AssessmentSession? tryFromJson(Map<String, Object?> json) {
    final String? sessionId = json['sessionId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? grade = json['grade'] as String?;
    final String? section = json['section'] as String?;
    final String? teacherUserId = json['teacherUserId'] as String?;
    final String? deviceId = json['deviceId'] as String?;
    final SessionStatus? status = SessionStatus.tryFromWireName(
      json['status'] as String?,
    );
    final DateTime? assessmentDate = _parseUtc(json['assessmentDate']);
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    if (sessionId == null ||
        assessmentId == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        grade == null ||
        section == null ||
        teacherUserId == null ||
        deviceId == null ||
        status == null ||
        assessmentDate == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return AssessmentSession(
      sessionId: sessionId,
      assessmentId: assessmentId,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      grade: grade,
      section: section,
      subject: json['subject'] as String? ?? '',
      academicYear: json['academicYear'] as String? ?? '',
      assessmentDate: assessmentDate,
      teacherUserId: teacherUserId,
      studentIds: (json['studentIds'] as List<Object?>? ?? const <Object?>[])
          .map((Object? id) => id.toString())
          .toList(growable: false),
      expectedStudentCount: (json['expectedStudentCount'] as num?)?.toInt() ?? 0,
      startedAt: _parseUtc(json['startedAt']),
      endedAt: _parseUtc(json['endedAt']),
      status: status,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
