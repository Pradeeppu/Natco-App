/// Seeds the demo assessments, questions, answer-key versions and
/// assignments.
///
/// Two assessments are seeded, on purpose in two different states, so the
/// demo build (and any widget test that pumps it) can show the whole answer
/// key story without needing to drive it interactively first:
///
/// * a fresh `DRAFT` assessment with no answer key yet — what a new
///   assessment looks like before anyone has touched it.
/// * an `ACTIVE` assessment with two answer-key versions: a `SUPERSEDED`
///   v1 and a `PUBLISHED` v2 carrying a change reason, and one assignment to
///   the first seeded school — the "a correction happened" story
///   (docs/02-data-model.md Critical Rules 5-6).
library;

import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assignment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

const List<String> _demoOptions = <String>['A', 'B', 'C', 'D'];

/// Populates [assessments] with the demo dataset, assigning the second
/// assessment to [seededSchools].first — the exact schools
/// `seedDemoMasterData` returns, so the assignment always names a real,
/// already-seeded school rather than guessing an id.
void seedDemoAssessmentData({
  required InMemoryAssessmentsRepository assessments,
  required List<School> seededSchools,
  required IdGenerator idGenerator,
  required Clock clock,
}) {
  final DateTime now = clock.nowUtc();

  // -- Assessment 1: a fresh draft, no answer key yet.
  final Assessment draft = Assessment(
    assessmentId: idGenerator.newId(),
    assessmentName: 'Term 1 Mathematics Assessment',
    assessmentCode: 'MATH-T1-2026',
    academicYear: '2026-27',
    grade: '5',
    subject: 'Mathematics',
    questionCount: 10,
    questionType: QuestionType.mcqSingle,
    options: _demoOptions,
    durationMinutes: 45,
    instructions: 'Answer all questions. Each question has a single correct option.',
    status: AssessmentStatus.draft,
    createdAt: now,
    updatedAt: now,
  );
  assessments.seedAssessment(
    draft,
    <AssessmentQuestion>[
      for (int n = 1; n <= draft.questionCount; n++)
        AssessmentQuestion(
          questionId: '${draft.assessmentId}_q$n',
          assessmentId: draft.assessmentId,
          questionNumber: n,
          marks: 1,
          createdAt: now,
          updatedAt: now,
        ),
    ],
  );

  // -- Assessment 2: active, with a corrected answer key and an assignment.
  final Assessment active = Assessment(
    assessmentId: idGenerator.newId(),
    assessmentName: 'Term 1 English Assessment',
    assessmentCode: 'ENG-T1-2026',
    academicYear: '2026-27',
    grade: '5',
    subject: 'English',
    questionCount: 5,
    questionType: QuestionType.mcqSingle,
    options: _demoOptions,
    durationMinutes: 30,
    instructions: 'Answer all questions. Each question has a single correct option.',
    activeAnswerKeyVersion: 2,
    status: AssessmentStatus.active,
    createdAt: now,
    updatedAt: now,
  );
  assessments.seedAssessment(
    active,
    <AssessmentQuestion>[
      for (int n = 1; n <= active.questionCount; n++)
        AssessmentQuestion(
          questionId: '${active.assessmentId}_q$n',
          assessmentId: active.assessmentId,
          questionNumber: n,
          marks: 1,
          createdAt: now,
          updatedAt: now,
        ),
    ],
  );

  const List<String> v1Answers = <String>['A', 'B', 'C', 'D', 'A'];
  final String v1Id = '${active.assessmentId}_v1';
  final String v2Id = '${active.assessmentId}_v2';
  assessments.seedAnswerKey(
    AnswerKey(
      answerKeyId: v1Id,
      assessmentId: active.assessmentId,
      version: 1,
      answers: <int, String>{
        for (int n = 1; n <= v1Answers.length; n++) n: v1Answers[n - 1],
      },
      status: AnswerKeyStatus.superseded,
      publishedBy: 'demo-assessment-admin',
      publishedAt: now,
      supersededBy: v2Id,
      createdAt: now,
    ),
  );
  // Version 2 corrects question 3 from C to B.
  const List<String> v2Answers = <String>['A', 'B', 'B', 'D', 'A'];
  assessments.seedAnswerKey(
    AnswerKey(
      answerKeyId: v2Id,
      assessmentId: active.assessmentId,
      version: 2,
      answers: <int, String>{
        for (int n = 1; n <= v2Answers.length; n++) n: v2Answers[n - 1],
      },
      status: AnswerKeyStatus.published,
      publishedBy: 'demo-assessment-admin',
      publishedAt: now,
      changeReason: 'Question 3 had two plausible readings; B is correct per the answer sheet.',
      createdAt: now,
    ),
  );

  if (seededSchools.isEmpty) {
    return;
  }
  final School school = seededSchools.first;
  assessments.seedAssignment(
    AssessmentAssignment(
      assignmentId: idGenerator.newId(),
      assessmentId: active.assessmentId,
      schoolId: school.schoolId,
      grade: active.grade,
      sections: const <String>['A', 'B'],
      assignedTeacherIds: const <String>[],
      expectedStudentCount: 40,
      status: AssignmentStatus.inProgress,
      createdAt: now,
      updatedAt: now,
    ),
  );
}
