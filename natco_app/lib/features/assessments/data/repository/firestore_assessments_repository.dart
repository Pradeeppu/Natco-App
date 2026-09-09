/// Firestore implementation of [AssessmentsRepository].
///
/// Answer keys use the documented deterministic document id
/// `{assessmentId}_v{version}` (docs/03-firestore-schema.md), which is what
/// lets `publishAnswerKey` find "the currently published version" with a
/// single `transaction.get` by reference — `Assessment.activeAnswerKeyVersion`
/// names which version that is — rather than a query, which the client SDK
/// cannot run inside a transaction. Publishing and superseding therefore
/// happen atomically: a reader never sees two `PUBLISHED` versions, nor a
/// published version whose predecessor was not marked `SUPERSEDED`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/data/remote/firestore_support.dart';
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

final class FirestoreAssessmentsRepository implements AssessmentsRepository {
  FirestoreAssessmentsRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  // ---------------------------------------------------------------- reads

  @override
  Future<Result<Page<Assessment>>> listAssessments({
    String? query,
    AssessmentStatus? status,
    PageRequest request = PageRequest.first,
  }) async {
    Query<Map<String, dynamic>> firestoreQuery = _firestore
        .collection(Collections.assessments)
        .orderBy('assessmentName')
        .orderBy(FieldPath.documentId);
    if (status != null) {
      firestoreQuery = firestoreQuery.where('status', isEqualTo: status.wireName);
    }
    if (query != null && query.trim().isNotEmpty) {
      final String prefix = query.trim();
      firestoreQuery = firestoreQuery
          .where('assessmentName', isGreaterThanOrEqualTo: prefix)
          .where(
            'assessmentName',
            isLessThan: firestorePrefixUpperBound(prefix),
          );
    }
    final FirestoreCursor? cursor = FirestoreCursor.tryDecode(request.cursor);
    if (cursor != null) {
      firestoreQuery = firestoreQuery.startAfter(<Object?>[
        cursor.orderValue,
        cursor.documentId,
      ]);
    }
    firestoreQuery = firestoreQuery.limit(request.limit);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(firestoreQuery.get, onError: mapFirestoreError);
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) => _pageFromDocs<Assessment>(
        value.docs,
        request.limit,
        orderValueOf: (Map<String, Object?> json) =>
            json['assessmentName'] as String? ?? '',
        fromJson: Assessment.tryFromJson,
      ),
    );
  }

  @override
  Future<Result<Assessment?>> getAssessment(String assessmentId) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.assessments)
              .doc(assessmentId)
              .get(),
          onError: mapFirestoreError,
        );
    return snapshot.flatMap(_assessmentFromDoc);
  }

  @override
  Future<Result<List<AssessmentQuestion>>> listQuestions(
    String assessmentId,
  ) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.assessmentQuestions)
              .where('assessmentId', isEqualTo: assessmentId)
              .orderBy('questionNumber')
              .get(),
          onError: mapFirestoreError,
        );
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) => <AssessmentQuestion>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in value.docs)
          if (AssessmentQuestion.tryFromJson(
                firestoreDocToJson(doc.data().cast<String, Object?>()),
              )
              case final AssessmentQuestion question)
            question,
      ],
    );
  }

  @override
  Future<Result<List<AnswerKey>>> listAnswerKeyVersions(
    String assessmentId,
  ) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.answerKeys)
              .where('assessmentId', isEqualTo: assessmentId)
              .orderBy('version')
              .get(),
          onError: mapFirestoreError,
        );
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) => <AnswerKey>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in value.docs)
          if (AnswerKey.tryFromJson(
                firestoreDocToJson(doc.data().cast<String, Object?>()),
              )
              case final AnswerKey key)
            key,
      ],
    );
  }

  @override
  Future<Result<AnswerKey?>> getPublishedAnswerKey(
    String assessmentId,
  ) async {
    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () => _firestore
              .collection(Collections.answerKeys)
              .where('assessmentId', isEqualTo: assessmentId)
              .where('status', isEqualTo: AnswerKeyStatus.published.wireName)
              .limit(1)
              .get(),
          onError: mapFirestoreError,
        );
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) => value.docs.isEmpty
          ? null
          : AnswerKey.tryFromJson(
              firestoreDocToJson(value.docs.first.data().cast<String, Object?>()),
            ),
    );
  }

  @override
  Future<Result<Page<AssessmentAssignment>>> listAssignments({
    required AccessScope scope,
    String? assessmentId,
    PageRequest request = PageRequest.first,
  }) async {
    Query<Map<String, dynamic>> firestoreQuery = _firestore
        .collection(Collections.assessmentAssignments)
        .orderBy(FieldPath.documentId);
    if (assessmentId != null) {
      firestoreQuery = firestoreQuery.where(
        'assessmentId',
        isEqualTo: assessmentId,
      );
    }
    if (!scope.isGlobal) {
      // Assignments carry only `schoolId` (docs/02-data-model.md section 4),
      // not the full denormalised ancestry `School` carries, so a scope wider
      // than a school cannot be pushed into this query the way
      // `FirestoreSchoolsRepository.listSchools` does — enforced instead by
      // the security rules reading the referenced school's ancestry
      // server-side, and by an explicit id filter here for a school-scoped
      // caller, the one case this client can express directly.
      if (scope.level == ScopeLevel.school) {
        firestoreQuery = firestoreQuery.where(
          'schoolId',
          whereIn: scope.schoolIds.toList(growable: false),
        );
      }
    }
    final FirestoreCursor? cursor = FirestoreCursor.tryDecode(request.cursor);
    if (cursor != null) {
      firestoreQuery = firestoreQuery.startAfter(<Object?>[cursor.documentId]);
    }
    firestoreQuery = firestoreQuery.limit(request.limit);

    final Result<QuerySnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(firestoreQuery.get, onError: mapFirestoreError);
    return snapshot.map(
      (QuerySnapshot<Map<String, dynamic>> value) =>
          _pageFromDocs<AssessmentAssignment>(
            value.docs,
            request.limit,
            orderValueOf: (Map<String, Object?> json) =>
                json['assignmentId'] as String? ?? '',
            fromJson: AssessmentAssignment.tryFromJson,
          ),
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
    if (questionCount <= 0 || options.isEmpty) {
      return err(
        const ValidationFailure(
          userMessage:
              'An assessment needs at least one question and one answer option.',
        ),
      );
    }
    // A uniqueness *check* here is advisory only, the same posture as
    // `FirestoreSchoolsRepository.createSchool`: the authoritative guard for
    // `assessmentCode` is server-side, not this client-side query.
    final Result<QuerySnapshot<Map<String, dynamic>>> existing = await guardAsync(
      () => _firestore
          .collection(Collections.assessments)
          .where('assessmentCode', isEqualTo: assessmentCode)
          .limit(1)
          .get(),
      onError: mapFirestoreError,
    );
    if (existing.isFailure) {
      return err(existing.failureOrNull!);
    }
    final QuerySnapshot<Map<String, dynamic>> existingDocs = existing.valueOrNull!;
    if (existingDocs.docs.isNotEmpty) {
      final Map<String, Object?> data = firestoreDocToJson(
        existingDocs.docs.first.data().cast<String, Object?>(),
      );
      return err(
        DuplicateFailure(
          userMessage:
              'Assessment code "$assessmentCode" is already used by '
              '"${data['assessmentName']}".',
          entityType: 'assessment',
          entityId: existingDocs.docs.first.id,
        ),
      );
    }

    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.assessments)
        .doc();
    final DateTime now = DateTime.now().toUtc();
    final Assessment assessment = Assessment(
      assessmentId: ref.id,
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

    final WriteBatch batch = _firestore.batch()
      ..set(
        ref,
        assessment.toJson()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp(),
      );
    for (int n = 1; n <= questionCount; n++) {
      final AssessmentQuestion question = AssessmentQuestion(
        questionId: '${ref.id}_q$n',
        assessmentId: ref.id,
        questionNumber: n,
        marks: marksPerQuestion,
        createdAt: now,
        updatedAt: now,
      );
      batch.set(
        _firestore.collection(Collections.assessmentQuestions).doc(question.questionId),
        question.toJson()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp(),
      );
    }
    final Result<void> write = await guardAsync(batch.commit, onError: mapFirestoreError);
    return write.fold(onSuccess: (_) => ok(assessment), onFailure: err);
  }

  @override
  Future<Result<Assessment>> updateAssessment(Assessment assessment) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.assessments)
        .doc(assessment.assessmentId);
    final Result<void> write = await guardAsync(
      () => ref.update(<String, Object?>{
        'assessmentName': assessment.assessmentName,
        'durationMinutes': assessment.durationMinutes,
        'instructions': assessment.instructions,
        'marksPerQuestion': assessment.marksPerQuestion,
        'negativeMarksPerWrong': assessment.negativeMarksPerWrong,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      onError: mapFirestoreError,
    );
    return write.fold(onSuccess: (_) => ok(assessment), onFailure: err);
  }

  @override
  Future<Result<Assessment>> setAssessmentStatus(
    String assessmentId,
    AssessmentStatus next,
  ) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.assessments)
        .doc(assessmentId);
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(ref.get, onError: mapFirestoreError);
    if (snapshot.isFailure) {
      return err(snapshot.failureOrNull!);
    }
    final Result<Assessment?> current = _assessmentFromDoc(snapshot.valueOrNull!);
    final Assessment? assessment = current.valueOrNull;
    if (assessment == null) {
      return current.isFailure
          ? err(current.failureOrNull!)
          : err(_assessmentNotFound(assessmentId));
    }
    if (!assessment.status.canTransitionTo(next)) {
      return err(
        IllegalStateTransitionFailure(
          entityType: 'assessment',
          from: assessment.status.wireName,
          to: next.wireName,
        ),
      );
    }
    if (next == AssessmentStatus.active && assessment.activeAnswerKeyVersion == null) {
      return err(
        const ValidationFailure(
          userMessage:
              'Publish an answer key before making this assessment active.',
        ),
      );
    }
    final Result<void> write = await guardAsync(
      () => ref.update(<String, Object?>{
        'status': next.wireName,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      onError: mapFirestoreError,
    );
    return write.fold(
      onSuccess: (_) => ok(assessment.copyWith(status: next)),
      onFailure: err,
    );
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
    final Result<Assessment?> assessmentResult = await getAssessment(assessmentId);
    if (assessmentResult.isFailure) {
      return err(assessmentResult.failureOrNull!);
    }
    final Assessment? assessment = assessmentResult.valueOrNull;
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
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.assessmentQuestions)
        .doc('${assessmentId}_q$questionNumber');
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(ref.get, onError: mapFirestoreError);
    if (snapshot.isFailure) {
      return err(snapshot.failureOrNull!);
    }
    final DocumentSnapshot<Map<String, dynamic>> doc = snapshot.valueOrNull!;
    final Map<String, dynamic>? data = doc.data();
    if (!doc.exists || data == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That question could not be found.',
          entityType: 'question',
          entityId: '$assessmentId#$questionNumber',
        ),
      );
    }
    final AssessmentQuestion? existing = AssessmentQuestion.tryFromJson(
      firestoreDocToJson(data.cast<String, Object?>()),
    );
    if (existing == null) {
      return err(
        const UnexpectedFailure(diagnostic: 'question document unreadable'),
      );
    }
    final AssessmentQuestion updated = existing.copyWith(
      marks: marks,
      topic: topic,
      difficulty: difficulty,
      options: options,
    );
    final Result<void> write = await guardAsync(
      () => ref.update(<String, Object?>{
        'marks': updated.marks,
        'topic': updated.topic,
        'difficulty': updated.difficulty,
        'options': updated.options,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      onError: mapFirestoreError,
    );
    return write.fold(onSuccess: (_) => ok(updated), onFailure: err);
  }

  @override
  Future<Result<AnswerKey>> publishAnswerKey({
    required String assessmentId,
    required Map<int, String> answers,
    String? publishedBy,
    String? changeReason,
  }) async {
    final Result<List<AssessmentQuestion>> questionsResult = await listQuestions(
      assessmentId,
    );
    if (questionsResult.isFailure) {
      return err(questionsResult.failureOrNull!);
    }
    final List<AssessmentQuestion> questions = questionsResult.valueOrNull!;
    if (questions.isEmpty) {
      return err(
        const ValidationFailure(
          userMessage: 'This assessment has no questions yet.',
        ),
      );
    }
    final Result<Assessment?> assessmentResult = await getAssessment(assessmentId);
    if (assessmentResult.isFailure) {
      return err(assessmentResult.failureOrNull!);
    }
    final Assessment? assessment = assessmentResult.valueOrNull;
    if (assessment == null) {
      return err(_assessmentNotFound(assessmentId));
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
    if (problems.isNotEmpty) {
      return err(
        ValidationFailure(
          userMessage:
              'The answer key is incomplete or invalid: ${problems.join('; ')}.',
        ),
      );
    }

    final int nextVersion = (assessment.activeAnswerKeyVersion ?? 0) + 1;
    if (nextVersion > 1 && (changeReason == null || changeReason.trim().isEmpty)) {
      return err(
        const ValidationFailure(
          userMessage:
              'A change reason is required to correct a published answer key.',
          fieldErrors: <String, String>{'changeReason': 'Required'},
        ),
      );
    }

    final DocumentReference<Map<String, dynamic>> assessmentRef = _firestore
        .collection(Collections.assessments)
        .doc(assessmentId);
    final DocumentReference<Map<String, dynamic>> newKeyRef = _firestore
        .collection(Collections.answerKeys)
        .doc('${assessmentId}_v$nextVersion');
    final DocumentReference<Map<String, dynamic>>? currentKeyRef =
        assessment.activeAnswerKeyVersion == null
        ? null
        : _firestore
              .collection(Collections.answerKeys)
              .doc('${assessmentId}_v${assessment.activeAnswerKeyVersion}');

    final DateTime now = DateTime.now().toUtc();
    final AnswerKey newKey = AnswerKey(
      answerKeyId: newKeyRef.id,
      assessmentId: assessmentId,
      version: nextVersion,
      answers: Map<int, String>.unmodifiable(answers),
      status: AnswerKeyStatus.published,
      publishedBy: publishedBy,
      publishedAt: now,
      changeReason: nextVersion > 1 ? changeReason!.trim() : null,
      createdAt: now,
    );

    try {
      await _firestore.runTransaction((Transaction transaction) async {
        if (currentKeyRef != null) {
          transaction.update(currentKeyRef, <String, Object?>{
            'status': AnswerKeyStatus.superseded.wireName,
            'supersededBy': newKeyRef.id,
          });
        }
        transaction.set(
          newKeyRef,
          newKey.toJson()..['publishedAt'] = FieldValue.serverTimestamp(),
        );
        transaction.update(assessmentRef, <String, Object?>{
          'activeAnswerKeyVersion': nextVersion,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (error, stackTrace) {
      return err(mapFirestoreError(error, stackTrace));
    }
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
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.assessmentAssignments)
        .doc();
    final DateTime now = DateTime.now().toUtc();
    final AssessmentAssignment assignment = AssessmentAssignment(
      assignmentId: ref.id,
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
    final Result<void> write = await guardAsync(
      () => ref.set(
        assignment.toJson()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp(),
      ),
      onError: mapFirestoreError,
    );
    return write.fold(onSuccess: (_) => ok(assignment), onFailure: err);
  }

  @override
  Future<Result<AssessmentAssignment>> setAssignmentStatus(
    String assignmentId,
    AssignmentStatus next,
  ) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.assessmentAssignments)
        .doc(assignmentId);
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(ref.get, onError: mapFirestoreError);
    if (snapshot.isFailure) {
      return err(snapshot.failureOrNull!);
    }
    final DocumentSnapshot<Map<String, dynamic>> doc = snapshot.valueOrNull!;
    final Map<String, dynamic>? data = doc.data();
    final AssessmentAssignment? existing = data == null
        ? null
        : AssessmentAssignment.tryFromJson(
            firestoreDocToJson(data.cast<String, Object?>()),
          );
    if (!doc.exists || existing == null) {
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
    final Result<void> write = await guardAsync(
      () => ref.update(<String, Object?>{
        'status': next.wireName,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      onError: mapFirestoreError,
    );
    return write.fold(
      onSuccess: (_) => ok(existing.copyWith(status: next)),
      onFailure: err,
    );
  }

  // -------------------------------------------------------------- helpers

  NotFoundFailure _assessmentNotFound(String assessmentId) => NotFoundFailure(
    userMessage: 'That assessment could not be found.',
    entityType: 'assessment',
    entityId: assessmentId,
  );

  Result<Assessment?> _assessmentFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic>? data = doc.data();
    if (!doc.exists || data == null) {
      return ok(null);
    }
    final Assessment? assessment = Assessment.tryFromJson(
      firestoreDocToJson(data.cast<String, Object?>()),
    );
    if (assessment == null) {
      return err(
        const UnexpectedFailure(diagnostic: 'assessment document unreadable'),
      );
    }
    return ok(assessment);
  }

  Page<T> _pageFromDocs<T>(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int limit, {
    required String Function(Map<String, Object?> json) orderValueOf,
    required T? Function(Map<String, Object?> json) fromJson,
  }) {
    final List<T> items = <T>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final Map<String, Object?> json = firestoreDocToJson(
        doc.data().cast<String, Object?>(),
      );
      final T? item = fromJson(json);
      if (item != null) {
        items.add(item);
      }
    }
    final bool hasMore = docs.length == limit && docs.isNotEmpty;
    String? nextCursor;
    if (hasMore) {
      final Map<String, Object?> lastJson = firestoreDocToJson(
        docs.last.data().cast<String, Object?>(),
      );
      nextCursor = FirestoreCursor(
        orderValue: orderValueOf(lastJson),
        documentId: docs.last.id,
      ).encode();
    }
    return Page<T>(items: items, nextCursor: nextCursor);
  }
}
