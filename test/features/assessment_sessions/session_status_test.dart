/// Tests for [SessionStatus]'s transition table and [AssessmentSession]'s
/// derived counts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';

AssessmentSession _session({
  SessionStatus status = SessionStatus.inProgress,
  List<SessionRosterEntry> roster = const <SessionRosterEntry>[],
}) => AssessmentSession(
  sessionId: 'ses_1',
  assessmentId: 'as_1',
  answerKeyVersion: 1,
  schoolId: 'sch_1',
  clusterId: 'cl_1',
  districtId: 'di_1',
  stateId: 'st_1',
  grade: '5',
  section: 'A',
  roster: roster,
  status: status,
  conductedBy: 'u1',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('SessionStatus transitions', () {
    test('ready may become in-progress or abandoned', () {
      expect(SessionStatus.ready.allowedNext, <SessionStatus>{
        SessionStatus.inProgress,
        SessionStatus.abandoned,
      });
    });

    test('in-progress may become completed or abandoned', () {
      expect(SessionStatus.inProgress.allowedNext, <SessionStatus>{
        SessionStatus.completed,
        SessionStatus.abandoned,
      });
    });

    test('completed and abandoned are both terminal', () {
      expect(SessionStatus.completed.allowedNext, isEmpty);
      expect(SessionStatus.abandoned.allowedNext, isEmpty);
    });

    test('a completed session cannot reopen', () {
      expect(
        SessionStatus.completed.canTransitionTo(SessionStatus.inProgress),
        isFalse,
      );
    });
  });

  group('isOpen and acceptsCapture', () {
    test('ready and in-progress are open; completed and abandoned are not', () {
      expect(SessionStatus.ready.isOpen, isTrue);
      expect(SessionStatus.inProgress.isOpen, isTrue);
      expect(SessionStatus.completed.isOpen, isFalse);
      expect(SessionStatus.abandoned.isOpen, isFalse);
    });

    test('only in-progress accepts capture', () {
      expect(SessionStatus.inProgress.acceptsCapture, isTrue);
      expect(SessionStatus.ready.acceptsCapture, isFalse);
      expect(SessionStatus.completed.acceptsCapture, isFalse);
      expect(SessionStatus.abandoned.acceptsCapture, isFalse);
    });
  });

  group('AssessmentSession derived counts', () {
    const roster = <SessionRosterEntry>[
      SessionRosterEntry(
        studentId: 's1',
        studentName: 'A',
        grade: '5',
        section: 'A',
        attendance: AttendanceState.captured,
        omrId: 'omr_1',
      ),
      SessionRosterEntry(
        studentId: 's2',
        studentName: 'B',
        grade: '5',
        section: 'A',
        attendance: AttendanceState.absent,
      ),
      SessionRosterEntry(
        studentId: 's3',
        studentName: 'C',
        grade: '5',
        section: 'A',
      ),
    ];

    test('counts captured, absent and pending separately', () {
      final session = _session(roster: roster);
      expect(session.capturedCount, 1);
      expect(session.absentCount, 1);
      expect(session.pendingCount, 1);
      expect(session.totalStudents, 3);
    });

    test('isFullyAccountedFor is false while anyone is pending', () {
      expect(_session(roster: roster).isFullyAccountedFor, isFalse);
    });

    test('isFullyAccountedFor is true once nobody is pending', () {
      final accounted = <SessionRosterEntry>[
        roster[0],
        roster[1],
        roster[2].copyWith(attendance: AttendanceState.captured),
      ];
      expect(_session(roster: accounted).isFullyAccountedFor, isTrue);
    });

    test('entryFor finds a roster row by student id', () {
      final session = _session(roster: roster);
      expect(session.entryFor('s2')!.attendance, AttendanceState.absent);
      expect(session.entryFor('unknown'), isNull);
    });
  });

  group('JSON round-trip', () {
    test('toJson/tryFromJson preserves the roster and status', () {
      const roster = <SessionRosterEntry>[
        SessionRosterEntry(
          studentId: 's1',
          studentName: 'A',
          grade: '5',
          section: 'A',
          attendance: AttendanceState.captured,
          omrId: 'omr_1',
        ),
      ];
      final original = _session(
        status: SessionStatus.completed,
        roster: roster,
      );
      final decoded = AssessmentSession.tryFromJson(original.toJson());

      expect(decoded, isNotNull);
      expect(decoded, original);
    });

    test('tryFromJson returns null for a missing required field', () {
      final json = _session().toJson()..remove('assessmentId');
      expect(AssessmentSession.tryFromJson(json), isNull);
    });
  });
}
