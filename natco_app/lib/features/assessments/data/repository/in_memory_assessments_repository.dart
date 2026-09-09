/// In-memory [AssessmentsRepository].
///
/// Powers demo mode and the test suite, the same posture as
/// `InMemorySchoolsRepository` and `InMemoryStudentsRepository`. An answer
/// key is never mutated in place here — `publishAnswerKey` is the only write
/// path, and it only ever appends a new version and flips a prior version's
/// status to `SUPERSEDED`; nothing in this class can edit an existing
/// [AnswerKey]'s `answers`.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assignment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';
import 'package:natco_app/features/assessments/domain/repository/assessments_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/data/repository/in_memory_schools_repository.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

final class InMemoryAssessmentsRepository implements AssessmentsRepository {
  InMemoryAssessmentsRepository({
    required IdGenerator idGenerator,
    required Clock clock,
    required InMemorySchoolsRepository schools,
  }) : _idGenerator = idGenerator,
       _clock = clock,
       _schools = schools;

  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Ancestry resolution only, mirroring
  /// `InMemoryStudentsRepository._schools` — an assignment's `schoolId` is
  /// the only ancestry it stores itself (docs/02-data-model.md section 4), so
  /// scoping [listAssignments] needs a lookup into the school it names.
  final InMemorySchoolsRepository _schools;

  final Map<String, Assessment> _assessments = <String, Assessment>{};
  final Set<String> _codesInUse = <String>{};
  final Map<String, List<AssessmentQuestion>> _questions =
      <String, List<AssessmentQuestion>>{};
  final Map<String, List<AnswerKey>> _answerKeys = <String, List<AnswerKey>>{};
  final Map<String, AssessmentAssignment> _assignments =
      <String, AssessmentAssignment>{};

  // ---------------------------------------------------------------- reads

  @override
  Future<Result<Page<Assessment>>> listAssessments({
    String? query,
    AssessmentStatus? status,
    PageRequest request = PageRequest.first,
  }) async {
    final String? needle = (query == null || query.trim().isEmpty)
        ? null
        : query.trim().toLowerCase();
    final List<Assessment> filtered = _assessments.values.where((
      Assessment a,
    ) {
      if (status != null && a.status != status) {
        return false;
      }
      if (needle != null && !a.assessmentName.toLowerCase().contains(needle)) {
        return false;
      }
      return true;
    }).toList();
    filtered.sort((Assessment a, Assessment b) {
      final int byName = a.assessmentName.toLowerCase().compareTo(
        b.assessmentName.toLowerCase(),
      );
      return byName != 0 ? byName : a.assessmentId.compareTo(b.assessmentId);
    });
    return ok(_paginate(filtered, request, (Assessment a) => a.assessmentId));
  }

  @override
  Future<Result<Assessment?>> getAssessment(String assessmentId) async =>
      ok(_assessments[assessmentId]);

  @override
  Future<Result<List<AssessmentQuestion>>> listQuestions(
    String assessmentId,
  ) async {
    if (!_assessments.containsKey(assessmentId)) {
      return err(_assessmentNotFound(assessmentId));
    }
    return ok(List<AssessmentQuestion>.of(_questions[assessmentId] ?? const <AssessmentQuestion>[]));
  }

  @override
  Future<Result<List<AnswerKey>>> listAnswerKeyVersions(
    String assessmentId,
  ) async {
    if (!_assessments.containsKey(assessmentId)) {
      return err(_assessmentNotFound(assessmentId));
    }
    return ok(List<AnswerKey>.of(_answerKeys[assessmentId] ?? const <AnswerKey>[]));
  }

  @override
  Future<Result<AnswerKey?>> getPublishedAnswerKey(
    String assessmentId,
  ) async {
    final List<AnswerKey> versions = _answerKeys[assessmentId] ?? const <AnswerKey>[];
    for (final AnswerKey key in versions) {
      if (key.status == AnswerKeyStatus.published) {
        return ok(key);
      }
    }
    return ok(null);
  }

  @override
  Future<Result<Page<AssessmentAssignment>>> listAssignments({
    required AccessScope scope,
    String? assessmentId,
    PageRequest request = PageRequest.first,
  }) async {
    final List<AssessmentAssignment> filtered = _assignments.values.where((
      AssessmentAssignment a,
    ) {
      if (assessmentId != null && a.assessmentId != assessmentId) {
        return false;
      }
      final School? school = _schools.schoolByIdUnchecked(a.schoolId);
      if (school == null) {
        return false;
      }
      return scope.covers(
        ScopeTarget(
          stateId: school.stateId,
          districtId: school.districtId,
          clusterId: school.clusterId,
          schoolId: school.schoolId,
        ),
      );
    }).toList();
    filtered.sort(
      (AssessmentAssignment a, AssessmentAssignment b) =>
          a.assignmentId.compareTo(b.assignmentId),
    );
    return ok(
      _paginate(filtered, request, (AssessmentAssignment a) => a.assignmentId),
    );
  }

  // --------------------------------------------------------------- writes

  @override
  Future<Result<Assessment>> createAssessment({
    required String assessmentName,
    required String assessmentCode,
    required String academicYear,
    required String grade,
    required String subject,
    required int questionCount,
    required QuestionType questionType,
    required List<String> options,
    required int durationMinutes,
    String instructions = '',
    double marksPerQuestion = 1,
    double negativeMarksPerWrong = 0,
  }) async {
    if (questionCount <= 0) {
      return err(
        const ValidationFailure(
          userMessage: 'An assessment needs at least one question.',
          fieldErrors: <String, String>{
            'questionCount': 'Must be at least 1',
          },
        ),
      );
    }
    if (options.isEmpty) {
      return err(
        const ValidationFailure(
          userMessage: 'An assessment needs at least one answer option.',
          fieldErrors: <String, String>{'options': 'Required'},
        ),
      );
    }
    final String normalisedCode = assessmentCode.trim().toLowerCase();
    if (_codesInUse.contains(normalisedCode)) {
      final Assessment existing = _assessments.values.firstWhere(
        (Assessment a) => a.assessmentCode.trim().toLowerCase() == normalisedCode,
      );
      return err(
        DuplicateFailure(
          userMessage:
              'Assessment code "$assessmentCode" is already used by '
              '"${existing.assessmentName}".',
          entityType: 'assessment',
          entityId: existing.assessmentId,
          details: <String, String>{
            'Assessment': existing.assessmentName,
            'Code': existing.assessmentCode,
          },
        ),
      );
    }

    final DateTime now = _clock.nowUtc();
    final Assessment assessment = Assessment(
      assessmentId: _idGenerator.newId(),
      assessmentName: assessmentName,
      assessmentCode: assessmentCode,
      academicYear: academicYear,
      grade: grade,
      subject: subject,
      questionCount: questionCount,
      questionType: questionType,
      options: List<String>.unmodifiable(options),
      durationMinutes: durationMinutes,
      instructions: instructions,
      marksPerQuestion: marksPerQuestion,
      negativeMarksPerWrong: negativeMarksPerWrong,
      status: AssessmentStatus.draft,
      createdAt: now,
      updatedAt: now,
    );
    _assessments[assessment.assessmentId] = assessment;
    _codesInUse.add(normalisedCode);
    _questions[assessment.assessmentId] = <AssessmentQuestion>[
      for (int n = 1; n <= questionCount; n++)
        AssessmentQuestion(
          questionId: _idGenerator.newId(),
          assessmentId: assessment.assessmentId,
          questionNumber: n,
          marks: marksPerQuestion,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    _answerKeys[assessment.assessmentId] = <AnswerKey>[];
    return ok(assessment);
  }

  @override
  Future<Result<Assessment>> updateAssessment(Assessment assessment) async {
    final Assessment? existing = _assessments[assessment.assessmentId];
    if (existing == null) {
      return err(_assessmentNotFound(assessment.assessmentId));
    }
    // assessmentId, assessmentCode, questionCount, questionType, options,
    // status and activeAnswerKeyVersion are not accepted from the caller —
    // the same "not by convention" posture as `School.updateSchool`.
    final Assessment updated = existing.copyWith(
      assessmentName: assessment.assessmentName,
      durationMinutes: assessment.durationMinutes,
      instructions: assessment.instructions,
      marksPerQuestion: assessment.marksPerQuestion,
      negativeMarksPerWrong: assessment.negativeMarksPerWrong,
      updatedAt: _clock.nowUtc(),
    );
    _assessments[updated.assessmentId] = updated;
    return ok(updated);
  }

  @override
  Future<Result<Assessment>> setAssessmentStatus(
    String assessmentId,
    AssessmentStatus next,
  ) async {
    final Assessment? existing = _assessments[assessmentId];
    if (existing == null) {
      return err(_assessmentNotFound(assessmentId));
    }
    if (!existing.status.canTransitionTo(next)) {
      return err(
        IllegalStateTransitionFailure(
          entityType: 'assessment',
          from: existing.status.wireName,
          to: next.wireName,
        ),
      );
    }
    if (next == AssessmentStatus.active && existing.activeAnswerKeyVersion == null) {
      return err(
        const ValidationFailure(
          userMessage:
              'Publish an answer key before making this assessment active.',
        ),
      );
    }
    final Assessment updated = existing.copyWith(
      status: next,
      updatedAt: _clock.nowUtc(),
    );
    _assessments[assessmentId] = updated;
    return ok(updated);
  }

  @override
  Future<Result<AssessmentQuestion>> updateQuestion({
    required String assessmentId,
    required int questionNumber,
    double? marks,
    String? topic,
    String? difficulty,
    List<String>? options,
  }) async {
    final Assessment? assessment = _assessments[assessmentId];
    if (assessment == null) {
      return err(_assessmentNotFound(assessmentId));
    }
    if (assessment.status != AssessmentStatus.draft) {
      return err(
        const ValidationFailure(
          userMessage:
              'Questions can only be edited while the assessment is still a draft.',
        ),
      );
    }
    final List<AssessmentQuestion> questions =
        _questions[assessmentId] ?? const <AssessmentQuestion>[];
    final int index = questions.indexWhere(
      (AssessmentQuestion q) => q.questionNumber == questionNumber,
    );
    if (index == -1) {
      return err(
        NotFoundFailure(
          userMessage: 'That question could not be found.',
          entityType: 'question',
          entityId: '$assessmentId#$questionNumber',
        ),
      );
    }
    final AssessmentQuestion updated = questions[index].copyWith(
      marks: marks,
      topic: topic,
      difficulty: difficulty,
      options: options,
      updatedAt: _clock.nowUtc(),
    );
    final List<AssessmentQuestion> next = List<AssessmentQuestion>.of(questions);
    next[index] = updated;
    _questions[assessmentId] = next;
    return ok(updated);
  }

  @override
  Future<Result<AnswerKey>> publishAnswerKey({
    required String assessmentId,
    required Map<int, String> answers,
    String? publishedBy,
    String? changeReason,
  }) async {
    final Assessment? assessment = _assessments[assessmentId];
    if (assessment == null) {
      return err(_assessmentNotFound(assessmentId));
    }
    final List<AssessmentQuestion> questions =
        _questions[assessmentId] ?? const <AssessmentQuestion>[];
    if (questions.isEmpty) {
      return err(
        const ValidationFailure(
          userMessage: 'This assessment has no questions yet.',
        ),
      );
    }

    final List<String> problems = <String>[];
    for (final AssessmentQuestion question in questions) {
      final String? answer = answers[question.questionNumber];
      final List<String> allowed = question.options ?? assessment.options;
      if (answer == null) {
        problems.add('question ${question.questionNumber} is missing an answer');
      } else if (!allowed.contains(answer)) {
        problems.add(
          'question ${question.questionNumber}\'s answer "$answer" is not '
          'one of ${allowed.join(', ')}',
        );
      }
    }
    final Set<int> validNumbers = questions
        .map((AssessmentQuestion q) => q.questionNumber)
        .toSet();
    final List<int> extra = answers.keys
        .where((int n) => !validNumbers.contains(n))
        .toList(growable: false)
      ..sort();
    for (final int n in extra) {
      problems.add('question $n does not exist on this assessment');
    }
    if (problems.isNotEmpty) {
      return err(
        ValidationFailure(
          userMessage:
              'The answer key is incomplete or invalid: ${problems.join('; ')}.',
        ),
      );
    }

    final List<AnswerKey> versions = List<AnswerKey>.of(
      _answerKeys[assessmentId] ?? const <AnswerKey>[],
    );
    AnswerKey? published;
    for (final AnswerKey key in versions) {
      if (key.status == AnswerKeyStatus.published) {
        published = key;
        break;
      }
    }
    final int nextVersion = versions.isEmpty
        ? 1
        : versions
                  .map((AnswerKey k) => k.version)
                  .reduce((int a, int b) => a > b ? a : b) +
              1;
    if (nextVersion > 1 && (changeReason == null || changeReason.trim().isEmpty)) {
      return err(
        const ValidationFailure(
          userMessage:
              'A change reason is required to correct a published answer key.',
          fieldErrors: <String, String>{'changeReason': 'Required'},
        ),
      );
    }

    final DateTime now = _clock.nowUtc();
    final AnswerKey newKey = AnswerKey(
      answerKeyId: _idGenerator.newId(),
      assessmentId: assessmentId,
      version: nextVersion,
      answers: Map<int, String>.unmodifiable(answers),
      status: AnswerKeyStatus.published,
      publishedBy: publishedBy,
      publishedAt: now,
      changeReason: nextVersion > 1 ? changeReason!.trim() : null,
      createdAt: now,
    );

    if (published != null) {
      final int publishedIndex = versions.indexOf(published);
      versions[publishedIndex] = published.supersededByVersion(newKey.answerKeyId);
    }
    versions.add(newKey);
    _answerKeys[assessmentId] = versions;
    _assessments[assessmentId] = assessment.copyWith(
      activeAnswerKeyVersion: nextVersion,
      updatedAt: now,
    );
    return ok(newKey);
  }

  @override
  Future<Result<AssessmentAssignment>> createAssignment({
    required String assessmentId,
    required String schoolId,
    required String grade,
    required List<String> sections,
    required List<String> assignedTeacherIds,
    required int expectedStudentCount,
    DateTime? dueDate,
  }) async {
    if (!_assessments.containsKey(assessmentId)) {
      return err(_assessmentNotFound(assessmentId));
    }
    if (_schools.schoolByIdUnchecked(schoolId) == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: schoolId,
        ),
      );
    }
    final DateTime now = _clock.nowUtc();
    final AssessmentAssignment assignment = AssessmentAssignment(
      assignmentId: _idGenerator.newId(),
      assessmentId: assessmentId,
      schoolId: schoolId,
      grade: grade,
      sections: List<String>.unmodifiable(sections),
      assignedTeacherIds: List<String>.unmodifiable(assignedTeacherIds),
      expectedStudentCount: expectedStudentCount,
      dueDate: dueDate,
      status: AssignmentStatus.assigned,
      createdAt: now,
      updatedAt: now,
    );
    _assignments[assignment.assignmentId] = assignment;
    return ok(assignment);
  }

  @override
  Future<Result<AssessmentAssignment>> setAssignmentStatus(
    String assignmentId,
    AssignmentStatus next,
  ) async {
    final AssessmentAssignment? existing = _assignments[assignmentId];
    if (existing == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That assignment could not be found.',
          entityType: 'assignment',
          entityId: assignmentId,
        ),
      );
    }
    if (!existing.status.canTransitionTo(next)) {
      return err(
        IllegalStateTransitionFailure(
          entityType: 'assignment',
          from: existing.status.wireName,
          to: next.wireName,
        ),
      );
    }
    final AssessmentAssignment updated = existing.copyWith(
      status: next,
      updatedAt: _clock.nowUtc(),
    );
    _assignments[assignmentId] = updated;
    return ok(updated);
  }

  // ------------------------------------------------------------- seeding

  /// Inserts a fully-formed assessment without validation, mirroring
  /// `InMemorySchoolsRepository.seedSchool` — used only by demo/seed data,
  /// which is known-good by construction.
  void seedAssessment(Assessment assessment, List<AssessmentQuestion> questions) {
    _assessments[assessment.assessmentId] = assessment;
    _codesInUse.add(assessment.assessmentCode.trim().toLowerCase());
    _questions[assessment.assessmentId] = List<AssessmentQuestion>.of(questions);
    _answerKeys[assessment.assessmentId] = <AnswerKey>[];
  }

  void seedAnswerKey(AnswerKey answerKey) {
    (_answerKeys[answerKey.assessmentId] ??= <AnswerKey>[]).add(answerKey);
  }

  void seedAssignment(AssessmentAssignment assignment) {
    _assignments[assignment.assignmentId] = assignment;
  }

  // -------------------------------------------------------------- helpers

  NotFoundFailure _assessmentNotFound(String assessmentId) => NotFoundFailure(
    userMessage: 'That assessment could not be found.',
    entityType: 'assessment',
    entityId: assessmentId,
  );

  Page<T> _paginate<T>(
    List<T> sorted,
    PageRequest request,
    String Function(T item) idOf,
  ) {
    int startIndex = 0;
    if (request.cursor != null) {
      final int cursorIndex = sorted.indexWhere(
        (T item) => idOf(item) == request.cursor,
      );
      startIndex = cursorIndex == -1 ? 0 : cursorIndex + 1;
    }
    final List<T> pageItems = sorted
        .skip(startIndex)
        .take(request.limit)
        .toList(growable: false);
    final bool hasMore = startIndex + pageItems.length < sorted.length;
    return Page<T>(
      items: pageItems,
      nextCursor: hasMore ? idOf(pageItems.last) : null,
    );
  }
}
