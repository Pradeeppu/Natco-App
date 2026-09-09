/// In-memory [AssessmentDataSource]. Backs demo mode and tests.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/data/service/assessment_data_source.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class InMemoryAssessmentDataSource implements AssessmentDataSource {
  InMemoryAssessmentDataSource({
    List<Assessment> assessments = const <Assessment>[],
    List<AnswerKey> answerKeys = const <AnswerKey>[],
    List<AssessmentAssignment> assignments = const <AssessmentAssignment>[],
  }) : _assessments = <String, Assessment>{
         for (final Assessment a in assessments) a.assessmentId: a,
       },
       _answerKeys = <String, AnswerKey>{
         for (final AnswerKey k in answerKeys) k.answerKeyId: k,
       },
       _assignments = <String, AssessmentAssignment>{
         for (final AssessmentAssignment a in assignments) a.assignmentId: a,
       };

  final Map<String, Assessment> _assessments;
  final Map<String, AnswerKey> _answerKeys;
  final Map<String, AssessmentAssignment> _assignments;

  @override
  Future<Result<Page<Assessment>>> listAssessments({
    required AccessScope scope,
    String query = '',
    AssessmentStatus? status,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final String needle = query.trim().toLowerCase();

    // An assessment is visible when at least one of its assignments falls
    // inside the caller's scope. A global scope sees everything, including an
    // assessment that has not been assigned anywhere yet — otherwise a
    // Super Admin could not see the draft they just created.
    final Set<String> visibleIds = scope.isGlobal
        ? _assessments.keys.toSet()
        : <String>{
            for (final AssessmentAssignment a in _assignments.values)
              if (scope.covers(
                ScopeTarget(
                  stateId: a.stateId,
                  districtId: a.districtId,
                  clusterId: a.clusterId,
                  schoolId: a.schoolId,
                  grade: a.grade,
                  // A grade-section-narrowed teacher matches when any of the
                  // assignment's sections is theirs. Passing a single section
                  // here cannot express that, so the sections are tested
                  // one at a time below.
                  section: a.sections.isEmpty ? null : a.sections.first,
                ),
              ) ||
                  a.sections.any(
                    (String section) => scope.covers(
                      ScopeTarget(
                        stateId: a.stateId,
                        districtId: a.districtId,
                        clusterId: a.clusterId,
                        schoolId: a.schoolId,
                        grade: a.grade,
                        section: section,
                      ),
                    ),
                  ))
                a.assessmentId,
          };

    final List<Assessment> matching =
        _assessments.values
            .where((Assessment a) => visibleIds.contains(a.assessmentId))
            .where((Assessment a) => status == null || a.status == status)
            .where(
              (Assessment a) =>
                  needle.isEmpty ||
                  a.assessmentName.toLowerCase().contains(needle) ||
                  a.subject.toLowerCase().contains(needle),
            )
            .toList()
          ..sort(
            (Assessment a, Assessment b) =>
                b.createdAt.compareTo(a.createdAt),
          );

    final int offset = cursor is int ? cursor : 0;
    final int end = (offset + pageSize).clamp(0, matching.length);
    final List<Assessment> items = offset >= matching.length
        ? const <Assessment>[]
        : matching.sublist(offset, end);
    final bool hasMore = end < matching.length;
    return ok((
      items: items,
      nextCursor: hasMore ? end : null,
      hasMore: hasMore,
    ));
  }

  @override
  Future<Result<Assessment>> getAssessment(String assessmentId) async {
    final Assessment? assessment = _assessments[assessmentId];
    if (assessment == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That assessment could not be found.',
          entityType: 'assessment',
          entityId: assessmentId,
        ),
      );
    }
    return ok(assessment);
  }

  @override
  Future<Result<Assessment>> createAssessment(Assessment assessment) async {
    if (_assessments.containsKey(assessment.assessmentId)) {
      return err(
        DuplicateFailure(
          userMessage: 'That assessment already exists.',
          entityType: 'assessment',
          entityId: assessment.assessmentId,
        ),
      );
    }
    _assessments[assessment.assessmentId] = assessment;
    return ok(assessment);
  }

  @override
  Future<Result<Assessment>> updateAssessment(Assessment assessment) async {
    if (!_assessments.containsKey(assessment.assessmentId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That assessment could not be found.',
          entityType: 'assessment',
          entityId: assessment.assessmentId,
        ),
      );
    }
    _assessments[assessment.assessmentId] = assessment;
    return ok(assessment);
  }

  @override
  Future<Result<List<AnswerKey>>> listAnswerKeys(String assessmentId) async =>
      ok(
        _answerKeys.values
            .where((AnswerKey k) => k.assessmentId == assessmentId)
            .toList()
          ..sort((AnswerKey a, AnswerKey b) => b.version.compareTo(a.version)),
      );

  @override
  Future<Result<AnswerKey>> saveAnswerKey(AnswerKey key) async {
    final AnswerKey? existing = _answerKeys[key.answerKeyId];
    if (existing != null && existing.isPublished) {
      // Critical Rule 7, enforced at the storage boundary as well as in the
      // policy: a published key is never rewritten, whatever asked.
      return err(
        ValidationFailure(
          userMessage:
              'Answer key version ${existing.version} has been published and '
              'cannot be changed.',
          diagnostic: 'write attempted on published key ${key.answerKeyId}',
        ),
      );
    }
    _answerKeys[key.answerKeyId] = key;
    return ok(key);
  }

  @override
  Future<Result<AnswerKey>> publishAnswerKey(AnswerKey key) async {
    final Assessment? assessment = _assessments[key.assessmentId];
    if (assessment == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That assessment could not be found.',
          entityType: 'assessment',
          entityId: key.assessmentId,
        ),
      );
    }
    final AnswerKey? existing = _answerKeys[key.answerKeyId];
    if (existing != null && existing.isPublished) {
      return err(
        ValidationFailure(
          userMessage: 'This answer key version is already published.',
          diagnostic: 'double publish of ${key.answerKeyId}',
        ),
      );
    }
    // Both writes together — see `AssessmentDataSource.publishAnswerKey`.
    _answerKeys[key.answerKeyId] = key;
    _assessments[assessment.assessmentId] = assessment.copyWith(
      publishedAnswerKeyVersion: key.version,
    );
    return ok(key);
  }

  @override
  Future<Result<List<AssessmentAssignment>>> listAssignments(
    String assessmentId,
  ) async => ok(
    _assignments.values
        .where((AssessmentAssignment a) => a.assessmentId == assessmentId)
        .toList(growable: false),
  );

  @override
  Future<Result<AssessmentAssignment>> saveAssignment(
    AssessmentAssignment assignment,
  ) async {
    final bool duplicate = _assignments.values.any(
      (AssessmentAssignment a) =>
          a.assignmentId != assignment.assignmentId &&
          a.assessmentId == assignment.assessmentId &&
          a.schoolId == assignment.schoolId &&
          a.grade == assignment.grade,
    );
    if (duplicate) {
      return err(
        DuplicateFailure(
          userMessage:
              'This school is already sitting this assessment for that grade.',
          entityType: 'assessment_assignment',
          entityId: assignment.assessmentId,
        ),
      );
    }
    _assignments[assignment.assignmentId] = assignment;
    return ok(assignment);
  }

  @override
  Future<Result<void>> deleteAssignment(String assignmentId) async {
    _assignments.remove(assignmentId);
    return ok(null);
  }
}
