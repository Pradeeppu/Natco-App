/// Tests for [InMemoryAssessmentsRepository]: creation validation, the
/// question-editing-only-while-draft rule, the status state machine, and
/// above all the two Phase 3 exit criteria (docs/08-mvp-implementation-plan.md):
/// a v1 answer key publishes and becomes immutable, and a correction
/// produces v2 with a reason and supersedes v1.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assignment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

void main() {
  late InMemorySchoolsRepository schoolsRepo;
  late InMemoryAssessmentsRepository repo;
  const IdGenerator idGenerator = UuidIdGenerator();
  final Clock clock = FixedClock(DateTime.utc(2026, 9, 9));

  School seedSchool(String name, String code, {String? clusterId, String? districtId, String? stateId}) {
    final DateTime now = clock.nowUtc();
    String cId = clusterId ?? '';
    String dId = districtId ?? '';
    String sId = stateId ?? '';
    if (clusterId == null) {
      final GeoNode state = GeoNode(
        id: idGenerator.newId(),
        level: HierarchyLevel.state,
        name: 'State',
        code: 'ST',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      schoolsRepo.seedState(state);
      final GeoNode district = GeoNode(
        id: idGenerator.newId(),
        level: HierarchyLevel.district,
        name: 'District',
        code: 'DI',
        isActive: true,
        createdAt: now,
        updatedAt: now,
        parentId: state.id,
        stateId: state.id,
      );
      schoolsRepo.seedDistrict(district);
      final GeoNode cluster = GeoNode(
        id: idGenerator.newId(),
        level: HierarchyLevel.cluster,
        name: 'Cluster',
        code: 'CL',
        isActive: true,
        createdAt: now,
        updatedAt: now,
        parentId: district.id,
        stateId: state.id,
        districtId: district.id,
      );
      schoolsRepo.seedCluster(cluster);
      cId = cluster.id;
      dId = district.id;
      sId = state.id;
    }
    final School school = School(
      schoolId: idGenerator.newId(),
      schoolName: name,
      schoolCode: code,
      clusterId: cId,
      districtId: dId,
      stateId: sId,
      grades: const <String>['5'],
      mediumsOfInstruction: const <String>['English'],
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    schoolsRepo.seedSchool(school);
    return school;
  }

  setUp(() {
    schoolsRepo = InMemorySchoolsRepository(idGenerator: idGenerator, clock: clock);
    repo = InMemoryAssessmentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schoolsRepo,
    );
  });

  Future<Assessment> createAssessment({int questionCount = 3}) async {
    final result = await repo.createAssessment(
      assessmentName: 'Term 1 Math',
      assessmentCode: 'MATH-T1',
      academicYear: '2026-27',
      grade: '5',
      subject: 'Mathematics',
      questionCount: questionCount,
      questionType: QuestionType.mcqSingle,
      options: const <String>['A', 'B', 'C', 'D'],
      durationMinutes: 30,
    );
    return result.valueOrNull!;
  }

  group('createAssessment', () {
    test('creates the assessment with the right number of questions', () async {
      final Assessment assessment = await createAssessment(questionCount: 5);
      expect(assessment.status, AssessmentStatus.draft);
      expect(assessment.activeAnswerKeyVersion, isNull);

      final questions = await repo.listQuestions(assessment.assessmentId);
      expect(questions.valueOrNull, hasLength(5));
      expect(
        questions.valueOrNull!.map((q) => q.questionNumber),
        <int>[1, 2, 3, 4, 5],
      );
    });

    test('rejects a duplicate assessment code with the existing identity', () async {
      await createAssessment();
      final result = await repo.createAssessment(
        assessmentName: 'Another Assessment',
        assessmentCode: 'math-t1', // same code, different case
        academicYear: '2026-27',
        grade: '5',
        subject: 'Mathematics',
        questionCount: 3,
        questionType: QuestionType.mcqSingle,
        options: const <String>['A', 'B', 'C', 'D'],
        durationMinutes: 30,
      );
      expect(result.failureOrNull, isA<DuplicateFailure>());
      final failure = result.failureOrNull! as DuplicateFailure;
      expect(failure.details['Assessment'], 'Term 1 Math');
    });

    test('rejects a zero question count', () async {
      final result = await repo.createAssessment(
        assessmentName: 'Bad Assessment',
        assessmentCode: 'BAD-1',
        academicYear: '2026-27',
        grade: '5',
        subject: 'Mathematics',
        questionCount: 0,
        questionType: QuestionType.mcqSingle,
        options: const <String>['A', 'B'],
        durationMinutes: 30,
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('updateQuestion', () {
    test('edits a question while the assessment is still a draft', () async {
      final Assessment assessment = await createAssessment();
      final result = await repo.updateQuestion(
        assessmentId: assessment.assessmentId,
        questionNumber: 2,
        marks: 2,
        topic: 'Fractions',
      );
      expect(result.valueOrNull?.marks, 2);
      expect(result.valueOrNull?.topic, 'Fractions');
    });

    test('refuses to edit a question once the assessment is published', () async {
      final Assessment assessment = await createAssessment();
      await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'C'},
      );
      await repo.setAssessmentStatus(
        assessment.assessmentId,
        AssessmentStatus.published,
      );
      final result = await repo.updateQuestion(
        assessmentId: assessment.assessmentId,
        questionNumber: 1,
        marks: 5,
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('status transitions', () {
    test('moves forward one legal step at a time', () async {
      final Assessment assessment = await createAssessment();
      await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'C'},
      );
      final published = await repo.setAssessmentStatus(
        assessment.assessmentId,
        AssessmentStatus.published,
      );
      expect(published.valueOrNull?.status, AssessmentStatus.published);

      final active = await repo.setAssessmentStatus(
        assessment.assessmentId,
        AssessmentStatus.active,
      );
      expect(active.valueOrNull?.status, AssessmentStatus.active);
    });

    test('rejects skipping a step', () async {
      final Assessment assessment = await createAssessment();
      final result = await repo.setAssessmentStatus(
        assessment.assessmentId,
        AssessmentStatus.active,
      );
      expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
    });

    test('refuses to activate an assessment with no published key', () async {
      final Assessment assessment = await createAssessment();
      await repo.setAssessmentStatus(
        assessment.assessmentId,
        AssessmentStatus.published,
      );
      final result = await repo.setAssessmentStatus(
        assessment.assessmentId,
        AssessmentStatus.active,
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('publishAnswerKey — the Phase 3 exit criteria', () {
    test('a v1 key publishes directly and becomes the active version', () async {
      final Assessment assessment = await createAssessment();
      final result = await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'C'},
      );
      final AnswerKey v1 = result.valueOrNull!;
      expect(v1.version, 1);
      expect(v1.status, AnswerKeyStatus.published);
      expect(v1.changeReason, isNull);

      final published = await repo.getPublishedAnswerKey(assessment.assessmentId);
      expect(published.valueOrNull?.answerKeyId, v1.answerKeyId);

      final refreshed = await repo.getAssessment(assessment.assessmentId);
      expect(refreshed.valueOrNull?.activeAnswerKeyVersion, 1);
    });

    test('publishing a correction without a reason is rejected', () async {
      final Assessment assessment = await createAssessment();
      await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'C'},
      );
      final result = await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'D'},
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
      final failure = result.failureOrNull! as ValidationFailure;
      expect(failure.fieldErrors, containsPair('changeReason', 'Required'));

      // v1 is untouched by the rejected attempt.
      final published = await repo.getPublishedAnswerKey(assessment.assessmentId);
      expect(published.valueOrNull?.version, 1);
    });

    test('a correction with a reason produces v2 and supersedes v1', () async {
      final Assessment assessment = await createAssessment();
      final v1Result = await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'C'},
      );
      final AnswerKey v1 = v1Result.valueOrNull!;

      final v2Result = await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'D'},
        changeReason: 'Question 3 answer sheet was misprinted.',
      );
      final AnswerKey v2 = v2Result.valueOrNull!;
      expect(v2.version, 2);
      expect(v2.status, AnswerKeyStatus.published);
      expect(v2.changeReason, 'Question 3 answer sheet was misprinted.');

      final versions = await repo.listAnswerKeyVersions(assessment.assessmentId);
      final AnswerKey storedV1 = versions.valueOrNull!.firstWhere(
        (k) => k.answerKeyId == v1.answerKeyId,
      );
      expect(storedV1.status, AnswerKeyStatus.superseded);
      expect(storedV1.supersededBy, v2.answerKeyId);
      // v1's original answers are preserved, not overwritten.
      expect(storedV1.answers, <int, String>{1: 'A', 2: 'B', 3: 'C'});

      final published = await repo.getPublishedAnswerKey(assessment.assessmentId);
      expect(published.valueOrNull?.answerKeyId, v2.answerKeyId);

      final refreshed = await repo.getAssessment(assessment.assessmentId);
      expect(refreshed.valueOrNull?.activeAnswerKeyVersion, 2);
    });

    test('rejects a key missing an answer or using an invalid option', () async {
      final Assessment assessment = await createAssessment();
      final missing = await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B'},
      );
      expect(missing.failureOrNull, isA<ValidationFailure>());

      final invalid = await repo.publishAnswerKey(
        assessmentId: assessment.assessmentId,
        answers: <int, String>{1: 'A', 2: 'B', 3: 'Z'},
      );
      expect(invalid.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('assignments', () {
    test('a cluster-scoped caller only sees assignments at their schools', () async {
      final School schoolA = seedSchool('School A', 'A1');
      final School schoolB = seedSchool('School B', 'B1');
      final Assessment assessment = await createAssessment();

      await repo.createAssignment(
        assessmentId: assessment.assessmentId,
        schoolId: schoolA.schoolId,
        grade: '5',
        sections: const <String>['A'],
        assignedTeacherIds: const <String>[],
        expectedStudentCount: 30,
      );
      await repo.createAssignment(
        assessmentId: assessment.assessmentId,
        schoolId: schoolB.schoolId,
        grade: '5',
        sections: const <String>['A'],
        assignedTeacherIds: const <String>[],
        expectedStudentCount: 25,
      );

      final scopedToA = AccessScope.singleSchool(schoolA.schoolId);
      final page = await repo.listAssignments(scope: scopedToA);
      expect(page.valueOrNull!.items, hasLength(1));
      expect(page.valueOrNull!.items.single.schoolId, schoolA.schoolId);

      final global = await repo.listAssignments(scope: const AccessScope.global());
      expect(global.valueOrNull!.items, hasLength(2));
    });

    test('setAssignmentStatus moves forward one step at a time', () async {
      final School school = seedSchool('School A', 'A1');
      final Assessment assessment = await createAssessment();
      final created = await repo.createAssignment(
        assessmentId: assessment.assessmentId,
        schoolId: school.schoolId,
        grade: '5',
        sections: const <String>['A'],
        assignedTeacherIds: const <String>[],
        expectedStudentCount: 30,
      );
      final assignmentId = created.valueOrNull!.assignmentId;

      final inProgress = await repo.setAssignmentStatus(
        assignmentId,
        AssignmentStatus.inProgress,
      );
      expect(inProgress.valueOrNull?.status, AssignmentStatus.inProgress);

      final skip = await repo.setAssignmentStatus(
        assignmentId,
        AssignmentStatus.assigned,
      );
      expect(skip.failureOrNull, isA<IllegalStateTransitionFailure>());
    });
  });
}
