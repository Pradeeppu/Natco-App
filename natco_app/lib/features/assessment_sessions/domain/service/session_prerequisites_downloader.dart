/// Fetches everything one assignment needs to run offline, and caches it.
///
/// The only place in the session-lifecycle feature that calls a
/// network-backed repository — `AssessmentSessionsRepository.startSession`
/// reads exclusively from the [SessionPrerequisitesRepository] this writes
/// into, never from `AssessmentsRepository`/`SchoolsRepository`/
/// `StudentsRepository` directly (docs/06-offline-sync-strategy.md §2).
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_prerequisites_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/assessments/domain/repository/assessments_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/schools_repository.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/repository/students_repository.dart';

final class SessionPrerequisitesDownloader {
  const SessionPrerequisitesDownloader({
    required AssessmentsRepository assessments,
    required SchoolsRepository schools,
    required StudentsRepository students,
    required SessionPrerequisitesRepository cache,
    required Clock clock,
  }) : _assessments = assessments,
       _schools = schools,
       _students = students,
       _cache = cache,
       _clock = clock;

  final AssessmentsRepository _assessments;
  final SchoolsRepository _schools;
  final StudentsRepository _students;
  final SessionPrerequisitesRepository _cache;
  final Clock _clock;

  Future<Result<SessionPrerequisites>> download(
    AssessmentAssignment assignment,
  ) async {
    final Result<Assessment?> assessmentResult = await _assessments
        .getAssessment(assignment.assessmentId);
    if (assessmentResult.isFailure) {
      return err(assessmentResult.failureOrNull!);
    }
    final Assessment? assessment = assessmentResult.valueOrNull;
    if (assessment == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That assessment could not be found.',
          entityType: 'assessment',
          entityId: assignment.assessmentId,
        ),
      );
    }

    final Result<List<AssessmentQuestion>> questionsResult = await _assessments
        .listQuestions(assignment.assessmentId);
    if (questionsResult.isFailure) {
      return err(questionsResult.failureOrNull!);
    }

    final Result<AnswerKey?> answerKeyResult = await _assessments
        .getPublishedAnswerKey(assignment.assessmentId);
    if (answerKeyResult.isFailure) {
      return err(answerKeyResult.failureOrNull!);
    }

    final Result<School?> schoolResult = await _schools.getSchool(
      assignment.schoolId,
      scope: const AccessScope.global(),
    );
    if (schoolResult.isFailure) {
      return err(schoolResult.failureOrNull!);
    }
    final School? school = schoolResult.valueOrNull;
    if (school == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: assignment.schoolId,
        ),
      );
    }

    final Map<String, List<String>> studentIdsBySection = <String, List<String>>{};
    for (final String section in assignment.sections) {
      final Result<Page<Student>> page = await _students.listStudents(
        scope: const AccessScope.global(),
        schoolId: assignment.schoolId,
        grade: assignment.grade,
        section: section,
        // A grade-section roster is a few dozen students at most, so one
        // page comfortably covers it — nothing here needs to scroll.
        request: const PageRequest(limit: 500),
      );
      if (page.isFailure) {
        return err(page.failureOrNull!);
      }
      studentIdsBySection[section] = page.valueOrNull!.items
          .map((Student s) => s.studentId)
          .toList(growable: false);
    }

    final SessionPrerequisites prerequisites = SessionPrerequisites(
      assignmentId: assignment.assignmentId,
      assessment: assessment,
      questions: questionsResult.valueOrNull!,
      publishedAnswerKey: answerKeyResult.valueOrNull,
      schoolId: school.schoolId,
      clusterId: school.clusterId,
      districtId: school.districtId,
      stateId: school.stateId,
      grade: assignment.grade,
      studentIdsBySection: studentIdsBySection,
      downloadedAt: _clock.nowUtc(),
    );

    final Result<void> saved = await _cache.save(prerequisites);
    return saved.fold(onSuccess: (_) => ok(prerequisites), onFailure: err);
  }
}
