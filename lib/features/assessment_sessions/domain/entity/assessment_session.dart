/// A sitting: one assessment, in one class, on one day
/// (docs/02-data-model.md §6).
///
/// The session is what makes offline capture safe. It is created on the
/// device, given an id there, and written locally before anything is sent —
/// so a teacher in a classroom with no signal is not waiting on a server to
/// tell them they may begin, and a force-stop mid-session loses nothing
/// (Critical Rule 12).
library;

/// Where a session is in its life.
///
/// [SessionStatus.abandoned] exists because the honest alternative is worse:
/// a session that is simply deleted takes its captured sheets' context with
/// it, and one left `inProgress` forever makes every "sessions still open"
/// count meaningless.
enum SessionStatus {
  /// Created and downloaded, not yet started. A session can sit here for days
  /// while a teacher prepares.
  ready('READY', 'Ready'),

  inProgress('IN_PROGRESS', 'In progress'),

  /// Every roster entry has been captured or explicitly marked absent.
  completed('COMPLETED', 'Completed'),

  /// Ended without finishing, with a reason. Sheets already captured are kept.
  abandoned('ABANDONED', 'Abandoned');

  const SessionStatus(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, SessionStatus> _byWireName = <String, SessionStatus>{
    for (final SessionStatus s in SessionStatus.values) s.wireName: s,
  };

  static SessionStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  bool get isOpen =>
      this == SessionStatus.ready || this == SessionStatus.inProgress;

  /// Whether sheets may be captured against it.
  bool get acceptsCapture => this == SessionStatus.inProgress;

  Set<SessionStatus> get allowedNext => switch (this) {
    SessionStatus.ready => const <SessionStatus>{
      SessionStatus.inProgress,
      SessionStatus.abandoned,
    },
    SessionStatus.inProgress => const <SessionStatus>{
      SessionStatus.completed,
      SessionStatus.abandoned,
    },
    // Both terminal. A completed session that could reopen would let sheets
    // arrive after its counts were rolled up into analytics.
    SessionStatus.completed => const <SessionStatus>{},
    SessionStatus.abandoned => const <SessionStatus>{},
  };

  bool canTransitionTo(SessionStatus next) => allowedNext.contains(next);
}

/// Why a student on the roster has no sheet.
enum AttendanceState {
  /// Not yet reached.
  pending('PENDING', 'Not yet captured'),

  /// A sheet has been captured for them.
  captured('CAPTURED', 'Captured'),

  /// Present in the class register but not sitting the paper.
  absent('ABSENT', 'Absent');

  const AttendanceState(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, AttendanceState> _byWireName =
      <String, AttendanceState>{
        for (final AttendanceState s in AttendanceState.values) s.wireName: s,
      };

  static AttendanceState tryFromWireName(String? name) =>
      name == null ? AttendanceState.pending : (_byWireName[name] ?? AttendanceState.pending);
}

/// One student's place in a session.
///
/// Holds the student's name so a roster renders offline without a second
/// lookup — the session is pre-downloaded whole, and a roster that needed the
/// student collection to render would be a roster that fails in a classroom
/// with no signal.
final class SessionRosterEntry {
  const SessionRosterEntry({
    required this.studentId,
    required this.studentName,
    required this.grade,
    required this.section,
    this.attendance = AttendanceState.pending,
    this.omrId,
    this.absenceNote,
  });

  final String studentId;
  final String studentName;
  final String grade;
  final String section;
  final AttendanceState attendance;

  /// The sheet captured for this student, once one has been.
  final String? omrId;

  final String? absenceNote;

  SessionRosterEntry copyWith({
    AttendanceState? attendance,
    String? omrId,
    String? absenceNote,
  }) => SessionRosterEntry(
    studentId: studentId,
    studentName: studentName,
    grade: grade,
    section: section,
    attendance: attendance ?? this.attendance,
    omrId: omrId ?? this.omrId,
    absenceNote: absenceNote ?? this.absenceNote,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'studentId': studentId,
    'studentName': studentName,
    'grade': grade,
    'section': section,
    'attendance': attendance.wireName,
    'omrId': omrId,
    'absenceNote': absenceNote,
  };

  static SessionRosterEntry? tryFromJson(Map<String, Object?> json) {
    final String? studentId = json['studentId'] as String?;
    final String? studentName = json['studentName'] as String?;
    final String? grade = json['grade'] as String?;
    final String? section = json['section'] as String?;
    if (studentId == null ||
        studentName == null ||
        grade == null ||
        section == null) {
      return null;
    }
    return SessionRosterEntry(
      studentId: studentId,
      studentName: studentName,
      grade: grade,
      section: section,
      attendance: AttendanceState.tryFromWireName(
        json['attendance'] as String?,
      ),
      omrId: json['omrId'] as String?,
      absenceNote: json['absenceNote'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionRosterEntry &&
      other.studentId == studentId &&
      other.studentName == studentName &&
      other.grade == grade &&
      other.section == section &&
      other.attendance == attendance &&
      other.omrId == omrId &&
      other.absenceNote == absenceNote;

  @override
  int get hashCode => Object.hash(
    studentId,
    studentName,
    grade,
    section,
    attendance,
    omrId,
    absenceNote,
  );

  /// Deliberately omits the student's name: this string can reach logs (§35).
  @override
  String toString() =>
      'SessionRosterEntry($studentId, ${attendance.wireName})';
}

final class AssessmentSession {
  const AssessmentSession({
    required this.sessionId,
    required this.assessmentId,
    required this.answerKeyVersion,
    required this.schoolId,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.grade,
    required this.section,
    required this.roster,
    required this.status,
    required this.conductedBy,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.endedAt,
    this.abandonReason,
    this.deviceId,
  });

  final String sessionId;
  final String assessmentId;

  /// The key version in force when the session started.
  ///
  /// Pinned at start rather than read at scoring time: a correction published
  /// mid-sitting must not silently change what this class was scored against
  /// without anyone re-deriving it. Phase 8's re-score is the deliberate path
  /// for that, and it supersedes rather than mutates.
  final int answerKeyVersion;

  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;
  final String grade;
  final String section;

  final List<SessionRosterEntry> roster;
  final SessionStatus status;

  final String conductedBy;

  /// The device the session was created on, for the audit trail and for
  /// spotting a session resumed somewhere unexpected.
  final String? deviceId;

  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? abandonReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get totalStudents => roster.length;

  int get capturedCount => roster
      .where((SessionRosterEntry e) => e.attendance == AttendanceState.captured)
      .length;

  int get absentCount => roster
      .where((SessionRosterEntry e) => e.attendance == AttendanceState.absent)
      .length;

  int get pendingCount => roster
      .where((SessionRosterEntry e) => e.attendance == AttendanceState.pending)
      .length;

  /// Whether every student has been accounted for — captured or marked
  /// absent. This is what gates completion: a session finished with students
  /// still pending would silently record them as neither.
  bool get isFullyAccountedFor => pendingCount == 0;

  SessionRosterEntry? entryFor(String studentId) {
    for (final SessionRosterEntry entry in roster) {
      if (entry.studentId == studentId) {
        return entry;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'assessmentId': assessmentId,
    'answerKeyVersion': answerKeyVersion,
    'schoolId': schoolId,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'grade': grade,
    'section': section,
    'roster': roster
        .map((SessionRosterEntry e) => e.toJson())
        .toList(growable: false),
    'status': status.wireName,
    'conductedBy': conductedBy,
    'deviceId': deviceId,
    'startedAt': startedAt?.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'abandonReason': abandonReason,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static AssessmentSession? tryFromJson(Map<String, Object?> json) {
    final String? sessionId = json['sessionId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? grade = json['grade'] as String?;
    final String? section = json['section'] as String?;
    final String? conductedBy = json['conductedBy'] as String?;
    final SessionStatus? status = SessionStatus.tryFromWireName(
      json['status'] as String?,
    );
    final int? answerKeyVersion = switch (json['answerKeyVersion']) {
      final num value => value.toInt(),
      _ => null,
    };
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    );
    if (sessionId == null ||
        assessmentId == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        grade == null ||
        section == null ||
        conductedBy == null ||
        status == null ||
        answerKeyVersion == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    final Object? rawRoster = json['roster'];
    final Object? startedAt = json['startedAt'];
    final Object? endedAt = json['endedAt'];
    return AssessmentSession(
      sessionId: sessionId,
      assessmentId: assessmentId,
      answerKeyVersion: answerKeyVersion,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      grade: grade,
      section: section,
      roster: rawRoster is Iterable
          ? rawRoster
                .whereType<Map<String, Object?>>()
                .map(SessionRosterEntry.tryFromJson)
                .whereType<SessionRosterEntry>()
                .toList(growable: false)
          : const <SessionRosterEntry>[],
      status: status,
      conductedBy: conductedBy,
      deviceId: json['deviceId'] as String?,
      startedAt: startedAt is String ? DateTime.tryParse(startedAt) : null,
      endedAt: endedAt is String ? DateTime.tryParse(endedAt) : null,
      abandonReason: json['abandonReason'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  AssessmentSession copyWith({
    List<SessionRosterEntry>? roster,
    SessionStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    String? abandonReason,
    DateTime? updatedAt,
  }) => AssessmentSession(
    sessionId: sessionId,
    assessmentId: assessmentId,
    answerKeyVersion: answerKeyVersion,
    schoolId: schoolId,
    clusterId: clusterId,
    districtId: districtId,
    stateId: stateId,
    grade: grade,
    section: section,
    roster: roster ?? this.roster,
    status: status ?? this.status,
    conductedBy: conductedBy,
    deviceId: deviceId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    abandonReason: abandonReason ?? this.abandonReason,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is AssessmentSession &&
      other.sessionId == sessionId &&
      other.assessmentId == assessmentId &&
      other.answerKeyVersion == answerKeyVersion &&
      other.schoolId == schoolId &&
      other.grade == grade &&
      other.section == section &&
      other.status == status &&
      other.conductedBy == conductedBy &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.abandonReason == abandonReason &&
      other.updatedAt == updatedAt &&
      _rosterEquals(other.roster, roster);

  @override
  int get hashCode => Object.hash(
    sessionId,
    assessmentId,
    answerKeyVersion,
    schoolId,
    grade,
    section,
    status,
    conductedBy,
    startedAt,
    endedAt,
    abandonReason,
    updatedAt,
    Object.hashAll(roster),
  );

  static bool _rosterEquals(
    List<SessionRosterEntry> a,
    List<SessionRosterEntry> b,
  ) {
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
  String toString() =>
      'AssessmentSession($sessionId, ${status.wireName}, '
      '$capturedCount/$totalStudents captured)';
}
