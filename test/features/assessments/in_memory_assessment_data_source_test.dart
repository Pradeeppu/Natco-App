/// Tests for [InMemoryAssessmentDataSource].
///
/// The one behaviour worth pinning at this layer, beyond plain CRUD: a
/// published answer key is refused a second write even if a caller bypasses
/// [AnswerKeyPolicy] entirely — the storage boundary enforces Critical Rule 7
/// on its own, not only the policy layer above it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessments/data/service/in_memory_assessment_data_source.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

Assessment _assessment(String id) => Assessment(
  assessmentId: id,
  assessmentName: 'Test $id',
  academicYear: '2026-27',
  grade: '5',
  subject: 'Maths',
  totalQuestions: 3,
  marksPerQuestion: 1,
  status: AssessmentStatus.draft,
  omrTemplateId: 'tpl_1',
  createdBy: 'u1',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

AnswerKey _key(String assessmentId, {bool isPublished = false, int version = 1}) =>
    AnswerKey(
      answerKeyId: '${assessmentId}_v$version',
      assessmentId: assessmentId,
      version: version,
      entries: const <AnswerKeyEntry>[
        AnswerKeyEntry(questionNumber: 1, correctOption: 'A'),
      ],
      isPublished: isPublished,
      createdBy: 'u1',
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('answer key immutability at the storage boundary', () {
    test('saveAnswerKey refuses to overwrite a published key', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1')],
        answerKeys: <AnswerKey>[_key('as_1', isPublished: true)],
      );

      final result = await source.saveAnswerKey(
        _key('as_1', isPublished: true).copyWith(
          entries: const <AnswerKeyEntry>[
            AnswerKeyEntry(questionNumber: 1, correctOption: 'D'),
          ],
        ),
      );

      expect(result.isFailure, isTrue);
    });

    test('saveAnswerKey allows overwriting a draft', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1')],
        answerKeys: <AnswerKey>[_key('as_1')],
      );

      final result = await source.saveAnswerKey(
        _key('as_1').copyWith(
          entries: const <AnswerKeyEntry>[
            AnswerKeyEntry(questionNumber: 1, correctOption: 'D'),
          ],
        ),
      );

      expect(result.isSuccess, isTrue);
    });

    test('publishAnswerKey refuses a second publish of the same version', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1')],
        answerKeys: <AnswerKey>[_key('as_1', isPublished: true)],
      );

      final result = await source.publishAnswerKey(_key('as_1'));
      expect(result.isFailure, isTrue);
    });

    test('publishAnswerKey updates the assessment atomically', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1')],
      );

      final published = await source.publishAnswerKey(
        _key('as_1', isPublished: true),
      );
      expect(published.isSuccess, isTrue);

      final assessment = await source.getAssessment('as_1');
      expect(assessment.valueOrNull!.publishedAnswerKeyVersion, 1);
    });
  });

  group('assignment-driven visibility', () {
    test('a global scope sees an assessment with no assignments', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1')],
      );
      final page = await source.listAssessments(
        scope: const AccessScope.global(),
      );
      expect(page.valueOrNull!.items, hasLength(1));
    });

    test('a scoped caller sees only assessments assigned to their schools', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1'), _assessment('as_2')],
        assignments: <AssessmentAssignment>[
          AssessmentAssignment(
            assignmentId: 'asg_1',
            assessmentId: 'as_1',
            schoolId: 'sch_1',
            clusterId: 'cl_1',
            districtId: 'di_1',
            stateId: 'st_1',
            grade: '5',
            assignedBy: 'u1',
            assignedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      final page = await source.listAssessments(
        scope: AccessScope.singleSchool('sch_1'),
      );
      expect(page.valueOrNull!.items.map((a) => a.assessmentId), <String>[
        'as_1',
      ]);
    });

    test('a school outside the assignment does not see the assessment', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1')],
        assignments: <AssessmentAssignment>[
          AssessmentAssignment(
            assignmentId: 'asg_1',
            assessmentId: 'as_1',
            schoolId: 'sch_1',
            clusterId: 'cl_1',
            districtId: 'di_1',
            stateId: 'st_1',
            grade: '5',
            assignedBy: 'u1',
            assignedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      final page = await source.listAssessments(
        scope: AccessScope.singleSchool('sch_2'),
      );
      expect(page.valueOrNull!.items, isEmpty);
    });
  });

  group('duplicate school+grade assignment', () {
    test('saveAssignment refuses a second assignment for the same school+grade', () async {
      final source = InMemoryAssessmentDataSource(
        assessments: <Assessment>[_assessment('as_1')],
      );
      final assignment = AssessmentAssignment(
        assignmentId: 'asg_1',
        assessmentId: 'as_1',
        schoolId: 'sch_1',
        clusterId: 'cl_1',
        districtId: 'di_1',
        stateId: 'st_1',
        grade: '5',
        assignedBy: 'u1',
        assignedAt: DateTime.utc(2026, 1, 1),
      );
      await source.saveAssignment(assignment);

      final duplicate = await source.saveAssignment(
        AssessmentAssignment(
          assignmentId: 'asg_2',
          assessmentId: 'as_1',
          schoolId: 'sch_1',
          clusterId: 'cl_1',
          districtId: 'di_1',
          stateId: 'st_1',
          grade: '5',
          assignedBy: 'u1',
          assignedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(duplicate.isFailure, isTrue);
    });
  });
}
