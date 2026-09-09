/// Seed data for demo mode: one in-progress session, with a mix of captured,
/// pending and absent students — so the session screen has every state it
/// needs to render without anyone having to run one first.
library;

import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessments/data/service/demo_assessment_data.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';

abstract final class DemoSessionIds {
  static const String inProgress = 'ses_demo_1';
}

List<AssessmentSession> demoSessions() {
  final DateTime createdAt = DateTime.utc(2026, 9, 15, 9);
  return <AssessmentSession>[
    AssessmentSession(
      sessionId: DemoSessionIds.inProgress,
      assessmentId: DemoAssessmentIds.midlineGrade5,
      answerKeyVersion: 1,
      schoolId: DemoHierarchyIds.schoolId1,
      clusterId: DemoHierarchyIds.clusterId1,
      districtId: DemoHierarchyIds.districtId1,
      stateId: DemoHierarchyIds.stateId,
      grade: '5',
      section: 'A',
      status: SessionStatus.inProgress,
      conductedBy: 'demo_teacher',
      deviceId: 'demo-device',
      startedAt: createdAt.add(const Duration(minutes: 5)),
      createdAt: createdAt,
      updatedAt: createdAt.add(const Duration(minutes: 40)),
      roster: <SessionRosterEntry>[
        const SessionRosterEntry(
          studentId: 'stu_demo_001',
          studentName: 'Aarav Sharma',
          grade: '5',
          section: 'A',
          attendance: AttendanceState.captured,
          omrId: '0001820',
        ),
        const SessionRosterEntry(
          studentId: 'stu_demo_002',
          studentName: 'Vivaan Verma',
          grade: '5',
          section: 'A',
          attendance: AttendanceState.captured,
          // Matches `DemoOmrIds.ambiguousSheet` in `demo_omr_data.dart` — the
          // sheet with the genuinely ambiguous Q17 that validation exists to
          // catch. Kept as this specific id because the layout and preview-
          // labelling tests already reference it.
          omrId: '0001827',
        ),
        const SessionRosterEntry(
          studentId: 'stu_demo_003',
          studentName: 'Aditya Reddy',
          grade: '5',
          section: 'A',
          attendance: AttendanceState.absent,
          absenceNote: 'Reported sick by parent',
        ),
        const SessionRosterEntry(
          studentId: 'stu_demo_004',
          studentName: 'Ishaan Iyer',
          grade: '5',
          section: 'A',
        ),
        const SessionRosterEntry(
          studentId: 'stu_demo_005',
          studentName: 'Kabir Nair',
          grade: '5',
          section: 'A',
        ),
      ],
    ),
  ];
}
