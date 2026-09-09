/// Seed data for demo mode: three assessments spanning the states the UI has
/// to render — a draft with no key, one published and being sat, and one
/// closed with a corrected key.
///
/// The third exists specifically so the answer-key history screen has real
/// history to show. A correction that only appears once someone performs one
/// is a screen nobody reviews.
///
/// Ids are shared with `DemoHierarchyIds` so assignments land on the demo
/// schools and the demo teacher's own class.
library;

import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';

abstract final class DemoAssessmentIds {
  static const String baselineGrade5 = 'as_demo_baseline_g5';
  static const String midlineGrade5 = 'as_demo_midline_g5';
  static const String baselineGrade7 = 'as_demo_baseline_g7';

  /// The OMR sheet layout these assessments are printed on (phase 6).
  static const String templateId = 'tpl_natco_50q_v1';

  static const String academicYear = '2026-27';
}

final DateTime _seed = DateTime.utc(2026, 4, 1);

List<Assessment> demoAssessments() => <Assessment>[
  Assessment(
    assessmentId: DemoAssessmentIds.midlineGrade5,
    assessmentName: 'Grade 5 Numeracy - Midline',
    academicYear: DemoAssessmentIds.academicYear,
    grade: '5',
    subject: 'Numeracy',
    description: 'Mid-year check against the baseline taken in April.',
    totalQuestions: 50,
    marksPerQuestion: 1,
    status: AssessmentStatus.active,
    omrTemplateId: DemoAssessmentIds.templateId,
    publishedAnswerKeyVersion: 1,
    scheduledDate: DateTime.utc(2026, 9, 15),
    createdBy: 'demo_assessment_admin',
    createdAt: _seed.add(const Duration(days: 120)),
    updatedAt: _seed.add(const Duration(days: 150)),
  ),
  Assessment(
    assessmentId: DemoAssessmentIds.baselineGrade5,
    assessmentName: 'Grade 5 Numeracy - Baseline',
    academicYear: DemoAssessmentIds.academicYear,
    grade: '5',
    subject: 'Numeracy',
    totalQuestions: 50,
    marksPerQuestion: 1,
    status: AssessmentStatus.closed,
    omrTemplateId: DemoAssessmentIds.templateId,
    // Version 2: this one carries a correction, so the history screen has
    // something real to show.
    publishedAnswerKeyVersion: 2,
    scheduledDate: DateTime.utc(2026, 4, 20),
    createdBy: 'demo_assessment_admin',
    createdAt: _seed,
    updatedAt: _seed.add(const Duration(days: 40)),
  ),
  Assessment(
    assessmentId: DemoAssessmentIds.baselineGrade7,
    assessmentName: 'Grade 7 Literacy - Baseline',
    academicYear: DemoAssessmentIds.academicYear,
    grade: '7',
    subject: 'Literacy',
    totalQuestions: 40,
    marksPerQuestion: 1,
    status: AssessmentStatus.draft,
    omrTemplateId: DemoAssessmentIds.templateId,
    createdBy: 'demo_assessment_admin',
    createdAt: _seed.add(const Duration(days: 160)),
    updatedAt: _seed.add(const Duration(days: 160)),
  ),
];

/// Deterministic answers, so a demo re-run scores identically.
///
/// `A`, `B`, `C`, `D` cycling by question number: arbitrary, but stable and
/// obviously synthetic — nobody will mistake it for a real key.
List<AnswerKeyEntry> _entries(int count, {Map<int, String> overrides = const {}}) =>
    <AnswerKeyEntry>[
      for (int q = 1; q <= count; q++)
        AnswerKeyEntry(
          questionNumber: q,
          correctOption: overrides[q] ?? kAnswerOptions[(q - 1) % 4],
        ),
    ];

List<AnswerKey> demoAnswerKeys() => <AnswerKey>[
  AnswerKey(
    answerKeyId: 'ak_demo_midline_v1',
    assessmentId: DemoAssessmentIds.midlineGrade5,
    version: 1,
    entries: _entries(50),
    isPublished: true,
    publishedAt: _seed.add(const Duration(days: 140)),
    createdBy: 'demo_assessment_admin',
    createdAt: _seed.add(const Duration(days: 130)),
  ),
  AnswerKey(
    answerKeyId: 'ak_demo_baseline_v1',
    assessmentId: DemoAssessmentIds.baselineGrade5,
    version: 1,
    entries: _entries(50),
    isPublished: true,
    publishedAt: _seed.add(const Duration(days: 10)),
    createdBy: 'demo_assessment_admin',
    createdAt: _seed.add(const Duration(days: 5)),
  ),
  AnswerKey(
    answerKeyId: 'ak_demo_baseline_v2',
    assessmentId: DemoAssessmentIds.baselineGrade5,
    version: 2,
    // Question 12's answer was wrong on v1. This is the shape of a real
    // correction: one question changed, everything else carried forward.
    entries: _entries(50, overrides: <int, String>{12: 'D'}),
    isPublished: true,
    publishedAt: _seed.add(const Duration(days: 40)),
    supersedesVersion: 1,
    changeReason:
        'Question 12 was keyed as C. The printed paper shows D as the only '
        'correct option; verified against the source paper.',
    createdBy: 'demo_assessment_admin',
    createdAt: _seed.add(const Duration(days: 38)),
  ),
];

List<AssessmentAssignment> demoAssignments() {
  final List<AssessmentAssignment> assignments = <AssessmentAssignment>[];
  const List<String> grade5Schools = <String>[
    DemoHierarchyIds.schoolId1,
    DemoHierarchyIds.schoolId2,
    DemoHierarchyIds.schoolId3,
  ];

  for (final String assessmentId in <String>[
    DemoAssessmentIds.midlineGrade5,
    DemoAssessmentIds.baselineGrade5,
  ]) {
    for (final String schoolId in grade5Schools) {
      assignments.add(
        AssessmentAssignment(
          assignmentId: 'asg_${assessmentId}_$schoolId',
          assessmentId: assessmentId,
          schoolId: schoolId,
          clusterId: _clusterOf(schoolId),
          districtId: _districtOf(schoolId),
          stateId: DemoHierarchyIds.stateId,
          grade: '5',
          // Both sections, so the demo teacher (5-A only) sees the assessment
          // while the scope check still keeps them out of 5-B's roster.
          sections: const <String>['A', 'B'],
          assignedBy: 'demo_assessment_admin',
          assignedAt: _seed,
        ),
      );
    }
  }
  return assignments;
}

String _clusterOf(String schoolId) => switch (schoolId) {
  DemoHierarchyIds.schoolId1 || DemoHierarchyIds.schoolId2 =>
    DemoHierarchyIds.clusterId1,
  DemoHierarchyIds.schoolId3 || DemoHierarchyIds.schoolId4 =>
    DemoHierarchyIds.clusterId2,
  _ => DemoHierarchyIds.clusterId3,
};

String _districtOf(String schoolId) =>
    schoolId == DemoHierarchyIds.schoolId5
    ? DemoHierarchyIds.districtId2
    : DemoHierarchyIds.districtId1;
