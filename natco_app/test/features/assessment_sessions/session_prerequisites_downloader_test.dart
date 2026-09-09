/// Tests for [SessionPrerequisitesDownloader]: it is the one place in the
/// session-lifecycle feature allowed to call a network-backed repository,
/// and what it produces is exactly what `startSession` needs to run with no
/// network at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/features/assessment_sessions/data/repository/in_memory_session_prerequisites_repository.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/service/session_prerequisites_downloader.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assignment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/geo_node.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';

void main() {
  late InMemorySchoolsRepository schools;
  late InMemoryStudentsRepository students;
  late InMemoryAssessmentsRepository assessments;
  late InMemorySessionPrerequisitesRepository cache;
  late SessionPrerequisitesDownloader downloader;
  const IdGenerator idGenerator = UuidIdGenerator();
  final Clock clock = FixedClock(DateTime.utc(2026, 9, 10));

  late School school;
  late Assessment assessment;
  late AssessmentAssignment assignment;

  setUp(() async {
    schools = InMemorySchoolsRepository(idGenerator: idGenerator, clock: clock);
    students = InMemoryStudentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    assessments = InMemoryAssessmentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    cache = InMemorySessionPrerequisitesRepository();
    downloader = SessionPrerequisitesDownloader(
      assessments: assessments,
      schools: schools,
      students: students,
      cache: cache,
      clock: clock,
    );

    final DateTime now = clock.nowUtc();
    final GeoNode state = GeoNode(
      id: idGenerator.newId(),
      level: HierarchyLevel.state,
      name: 'State',
      code: 'ST',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    schools.seedState(state);
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
    schools.seedDistrict(district);
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
    schools.seedCluster(cluster);
    school = School(
      schoolId: idGenerator.newId(),
      schoolName: 'Test School',
      schoolCode: 'TS1',
      clusterId: cluster.id,
      districtId: district.id,
      stateId: state.id,
      grades: const <String>['5'],
      mediumsOfInstruction: const <String>['English'],
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    schools.seedSchool(school);

    students.seedStudent(
      schoolId: school.schoolId,
      studentName: 'Section A Student',
      gender: Gender.male,
      grade: '5',
      section: 'A',
      mediumOfInstruction: 'English',
      language: 'English',
    );
    students.seedStudent(
      schoolId: school.schoolId,
      studentName: 'Section B Student One',
      gender: Gender.female,
      grade: '5',
      section: 'B',
      mediumOfInstruction: 'English',
      language: 'English',
    );
    students.seedStudent(
      schoolId: school.schoolId,
      studentName: 'Section B Student Two',
      gender: Gender.female,
      grade: '5',
      section: 'B',
      mediumOfInstruction: 'English',
      language: 'English',
    );

    final assessmentResult = await assessments.createAssessment(
      assessmentName: 'Term 1 Math',
      assessmentCode: 'MATH-T1',
      academicYear: '2026-27',
      grade: '5',
      subject: 'Mathematics',
      questionCount: 3,
      questionType: QuestionType.mcqSingle,
      options: const <String>['A', 'B', 'C', 'D'],
      durationMinutes: 30,
    );
    assessment = assessmentResult.valueOrNull!;

    final assignmentResult = await assessments.createAssignment(
      assessmentId: assessment.assessmentId,
      schoolId: school.schoolId,
      grade: '5',
      sections: const <String>['A', 'B'],
      assignedTeacherIds: const <String>[],
      expectedStudentCount: 3,
    );
    assignment = assignmentResult.valueOrNull!;
  });

  test('downloads and caches everything a session needs', () async {
    await assessments.publishAnswerKey(
      assessmentId: assessment.assessmentId,
      answers: <int, String>{1: 'A', 2: 'B', 3: 'C'},
    );

    final result = await downloader.download(assignment);
    expect(result.isSuccess, isTrue);
    final SessionPrerequisites prerequisites = result.valueOrNull!;

    expect(prerequisites.assessment.assessmentId, assessment.assessmentId);
    expect(prerequisites.questions, hasLength(3));
    expect(prerequisites.publishedAnswerKey?.answers, <int, String>{
      1: 'A',
      2: 'B',
      3: 'C',
    });
    expect(prerequisites.schoolId, school.schoolId);
    expect(prerequisites.clusterId, school.clusterId);
    expect(prerequisites.districtId, school.districtId);
    expect(prerequisites.stateId, school.stateId);
    expect(prerequisites.studentIdsBySection['A'], hasLength(1));
    expect(prerequisites.studentIdsBySection['B'], hasLength(2));

    // Cached, so a later read needs no repository call.
    final cached = await cache.get(assignment.assignmentId);
    expect(cached.valueOrNull?.assignmentId, assignment.assignmentId);
  });

  test('an un-keyed assessment downloads with a null answer key, not an error', () async {
    final result = await downloader.download(assignment);
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull?.publishedAnswerKey, isNull);
  });

  test('fails cleanly for an assignment pointing at a school that no longer exists', () async {
    final ghostAssignment = AssessmentAssignment(
      assignmentId: idGenerator.newId(),
      assessmentId: assessment.assessmentId,
      schoolId: 'does-not-exist',
      grade: '5',
      sections: const <String>['A'],
      assignedTeacherIds: const <String>[],
      expectedStudentCount: 10,
      status: AssignmentStatus.assigned,
      createdAt: clock.nowUtc(),
      updatedAt: clock.nowUtc(),
    );
    final result = await downloader.download(ghostAssignment);
    expect(result.isFailure, isTrue);
  });
}
