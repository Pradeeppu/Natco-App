/// Tests for the demo assessment dataset generator.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/data/local/demo_assessment_data.dart';
import 'package:natco_app/data/local/demo_master_data.dart';
import 'package:natco_app/features/assessments/data/repository/in_memory_assessments_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/students/data/repository/in_memory_students_repository.dart';

void main() {
  late InMemorySchoolsRepository schools;
  late InMemoryAssessmentsRepository assessments;

  setUp(() {
    const IdGenerator idGenerator = UuidIdGenerator();
    final Clock clock = FixedClock(DateTime.utc(2026, 9, 9));
    schools = InMemorySchoolsRepository(idGenerator: idGenerator, clock: clock);
    final students = InMemoryStudentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    assessments = InMemoryAssessmentsRepository(
      idGenerator: idGenerator,
      clock: clock,
      schools: schools,
    );
    final List<School> seededSchools = seedDemoMasterData(
      schools: schools,
      students: students,
      idGenerator: idGenerator,
      clock: clock,
    );
    seedDemoAssessmentData(
      assessments: assessments,
      seededSchools: seededSchools,
      idGenerator: idGenerator,
      clock: clock,
    );
  });

  test('seeds one draft assessment with no answer key', () async {
    final page = await assessments.listAssessments(status: AssessmentStatus.draft);
    expect(page.valueOrNull!.items, hasLength(1));
    final Assessment draft = page.valueOrNull!.items.single;
    expect(draft.activeAnswerKeyVersion, isNull);

    final versions = await assessments.listAnswerKeyVersions(draft.assessmentId);
    expect(versions.valueOrNull, isEmpty);
  });

  test('seeds one active assessment with a corrected answer key', () async {
    final page = await assessments.listAssessments(status: AssessmentStatus.active);
    expect(page.valueOrNull!.items, hasLength(1));
    final Assessment active = page.valueOrNull!.items.single;
    expect(active.activeAnswerKeyVersion, 2);

    final versions = await assessments.listAnswerKeyVersions(active.assessmentId);
    expect(versions.valueOrNull, hasLength(2));
    final AnswerKey v1 = versions.valueOrNull!.firstWhere((k) => k.version == 1);
    final AnswerKey v2 = versions.valueOrNull!.firstWhere((k) => k.version == 2);
    expect(v1.status, AnswerKeyStatus.superseded);
    expect(v1.supersededBy, v2.answerKeyId);
    expect(v2.status, AnswerKeyStatus.published);
    expect(v2.changeReason, isNotNull);
  });

  test('assigns the active assessment to a real, seeded school', () async {
    final page = await assessments.listAssessments(status: AssessmentStatus.active);
    final Assessment active = page.valueOrNull!.items.single;

    final assignments = await assessments.listAssignments(
      scope: const AccessScope.global(),
      assessmentId: active.assessmentId,
    );
    expect(assignments.valueOrNull!.items, hasLength(1));
    final String schoolId = assignments.valueOrNull!.items.single.schoolId;

    final school = await schools.getSchool(
      schoolId,
      scope: const AccessScope.global(),
    );
    expect(school.valueOrNull, isNotNull);
  });
}
