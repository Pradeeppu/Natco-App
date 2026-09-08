/// Firestore implementation of [StudentsRepository].
///
/// The one behaviour worth reading carefully here is [createStudent]: it runs
/// inside a transaction that reads `student_dedupe/{dedupeKey}` and writes the
/// student only when that guard document does not already exist
/// (docs/03-firestore-schema.md). That is what makes "never merge a
/// duplicate" atomic rather than a racy read-then-write — two teachers
/// importing the same child at the same moment cannot both succeed.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/data/remote/firestore_support.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_import_report.dart';
import 'package:natco_app/features/students/domain/repository/students_repository.dart';

final class FirestoreStudentsRepository implements StudentsRepository {
  FirestoreStudentsRepository({
    required FirebaseFirestore firestore,
    required IdGenerator idGenerator,
  }) : _firestore = firestore,
       _idGenerator = idGenerator;

  final FirebaseFirestore _firestore;
  final IdGenerator _idGenerator;

  // ---------------------------------------------------------------- reads

  @override
  Future<Result<Page<Student>>> listStudents({
    required AccessScope scope,
    required String schoolId,
    String? grade,
    String? section,
    String? query,
    PageRequest request = PageRequest.first,
  }) async {
    Query<Map<String, dynamic>> firestoreQuery = _firestore
        .collection(Collections.students)
        .where('schoolId', isEqualTo: schoolId)
        .orderBy('studentName')
        .orderBy(FieldPath.documentId);
    if (grade != null) {
      firestoreQuery = firestoreQuery.where('grade', isEqualTo: grade);
    }
    if (section != null) {
      firestoreQuery = firestoreQuery.where('section', isEqualTo: section);
    }
    if (query != null && query.trim().isNotEmpty) {
      // A prefix search, same trade-off as `FirestoreSchoolsRepository`: this
      // box is for jumping to a student by name, not full-text search.
      final String prefix = query.trim();
      firestoreQuery = firestoreQuery
          .where('studentName', isGreaterThanOrEqualTo: prefix)
          .where('studentName', isLessThan: firestorePrefixUpperBound(prefix));
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
    return switch (snapshot) {
      FailureResult<QuerySnapshot<Map<String, dynamic>>>(:final failure) =>
        err(failure),
      Success<QuerySnapshot<Map<String, dynamic>>>(:final value) => ok(
        _pageFromDocs(value.docs, request.limit, scope),
      ),
    };
  }

  @override
  Future<Result<Student?>> getStudent(
    String studentId, {
    required AccessScope scope,
  }) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> snapshot =
        await guardAsync(
          () =>
              _firestore.collection(Collections.students).doc(studentId).get(),
          onError: mapFirestoreError,
        );
    return switch (snapshot) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(:final failure) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(:final value) =>
        _mapStudentDoc(value, scope),
    };
  }

  Result<Student?> _mapStudentDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    AccessScope scope,
  ) {
    final Map<String, dynamic>? data = doc.data();
    if (!doc.exists || data == null) {
      return ok(null);
    }
    final Student? student = Student.tryFromJson(
      firestoreDocToJson(data.cast<String, Object?>()),
    );
    if (student == null) {
      return err(
        const UnexpectedFailure(diagnostic: 'student document unreadable'),
      );
    }
    if (!scope.covers(
      ScopeTarget(
        stateId: student.stateId,
        districtId: student.districtId,
        clusterId: student.clusterId,
        schoolId: student.schoolId,
        grade: student.grade,
        section: student.section,
      ),
    )) {
      return err(PermissionFailure.outOfScope());
    }
    return ok(student);
  }

  // --------------------------------------------------------------- writes

  @override
  Future<Result<Student>> createStudent({
    required String schoolId,
    required String studentName,
    required Gender gender,
    required String grade,
    required String section,
    required String mediumOfInstruction,
    required String language,
    DateTime? dateOfBirth,
    String? electiveSubject,
    String? externalStudentCode,
  }) async {
    final Result<DocumentSnapshot<Map<String, dynamic>>> schoolSnapshot =
        await guardAsync(
          () => _firestore.collection(Collections.schools).doc(schoolId).get(),
          onError: mapFirestoreError,
        );
    return switch (schoolSnapshot) {
      FailureResult<DocumentSnapshot<Map<String, dynamic>>>(:final failure) =>
        err(failure),
      Success<DocumentSnapshot<Map<String, dynamic>>>(:final value) =>
        await _createStudentInSchool(
          schoolDoc: value,
          schoolId: schoolId,
          studentName: studentName,
          gender: gender,
          grade: grade,
          section: section,
          mediumOfInstruction: mediumOfInstruction,
          language: language,
          dateOfBirth: dateOfBirth,
          electiveSubject: electiveSubject,
          externalStudentCode: externalStudentCode,
        ),
    };
  }

  Future<Result<Student>> _createStudentInSchool({
    required DocumentSnapshot<Map<String, dynamic>> schoolDoc,
    required String schoolId,
    required String studentName,
    required Gender gender,
    required String grade,
    required String section,
    required String mediumOfInstruction,
    required String language,
    required DateTime? dateOfBirth,
    required String? electiveSubject,
    required String? externalStudentCode,
  }) async {
    final Map<String, dynamic>? schoolData = schoolDoc.data();
    if (!schoolDoc.exists || schoolData == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That school could not be found.',
          entityType: 'school',
          entityId: schoolId,
        ),
      );
    }
    final String? clusterId = schoolData['clusterId'] as String?;
    final String? districtId = schoolData['districtId'] as String?;
    final String? stateId = schoolData['stateId'] as String?;
    if (clusterId == null || districtId == null || stateId == null) {
      return err(
        const UnexpectedFailure(diagnostic: 'school document missing ancestry'),
      );
    }

    final String dedupeKey = _idGenerator.dedupeKey(<String>[
      schoolId,
      studentName,
      grade,
      section,
      dateOfBirth?.toIso8601String() ?? '',
    ]);
    final DocumentReference<Map<String, dynamic>> dedupeRef = _firestore
        .collection(Collections.studentDedupe)
        .doc(dedupeKey);
    final DocumentReference<Map<String, dynamic>> studentRef = _firestore
        .collection(Collections.students)
        .doc();
    final DateTime now = DateTime.now().toUtc();
    final Student student = Student(
      studentId: studentRef.id,
      externalStudentCode: externalStudentCode,
      studentName: studentName,
      gender: gender,
      dateOfBirth: dateOfBirth,
      grade: grade,
      section: section,
      mediumOfInstruction: mediumOfInstruction,
      language: language,
      electiveSubject: electiveSubject,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      activeStatus: true,
      dedupeKey: dedupeKey,
      createdAt: now,
      updatedAt: now,
    );

    final Result<_TransactionOutcome> outcome = await guardAsync(
      () => _firestore.runTransaction<_TransactionOutcome>((
        Transaction transaction,
      ) async {
        final DocumentSnapshot<Map<String, dynamic>> guard = await transaction
            .get(dedupeRef);
        if (guard.exists) {
          return _TransactionOutcome.duplicate(
            guard.data()?['studentId'] as String? ?? '',
          );
        }
        transaction.set(dedupeRef, <String, Object?>{
          'studentId': student.studentId,
          'schoolId': schoolId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(
          studentRef,
          student.toJson()
            ..['createdAt'] = FieldValue.serverTimestamp()
            ..['updatedAt'] = FieldValue.serverTimestamp(),
        );
        return const _TransactionOutcome.created();
      }),
      onError: mapFirestoreError,
    );

    return switch (outcome) {
      FailureResult<_TransactionOutcome>(:final failure) => err(failure),
      Success<_TransactionOutcome>(value: _Created()) => ok(student),
      Success<_TransactionOutcome>(
        value: _Duplicate(:final existingStudentId),
      ) =>
        await _duplicateFailure(existingStudentId),
    };
  }

  Future<Result<Student>> _duplicateFailure(String existingStudentId) async {
    if (existingStudentId.isEmpty) {
      return err(
        const DuplicateFailure(
          userMessage: 'This student is already enrolled.',
          entityType: 'student',
          entityId: 'unknown',
        ),
      );
    }
    final Result<Student?> existing = await getStudent(
      existingStudentId,
      scope: const AccessScope.global(),
    );
    final Student? student = existing.valueOrNull;
    return err(
      DuplicateFailure(
        userMessage: student == null
            ? 'This student is already enrolled.'
            : '"${student.studentName}" is already enrolled in '
                  '${student.grade}-${student.section} at this school.',
        entityType: 'student',
        entityId: existingStudentId,
        details: student == null
            ? const <String, String>{}
            : <String, String>{
                'Student': student.studentName,
                'Grade': student.grade,
                'Section': student.section,
              },
      ),
    );
  }

  @override
  Future<Result<Student>> updateStudent(Student student) async {
    // A name/grade/section/dob edit that changes the dedupe key needs the
    // same transactional guard as a create — otherwise an edit could collide
    // silently with another student's record. Handled the same way: read the
    // existing record first to know whether the key is actually changing.
    final Result<Student?> current = await getStudent(
      student.studentId,
      scope: const AccessScope.global(),
    );
    return switch (current) {
      FailureResult<Student?>(:final failure) => err(failure),
      Success<Student?>(value: null) => err(
        NotFoundFailure(
          userMessage: 'That student could not be found.',
          entityType: 'student',
          entityId: student.studentId,
        ),
      ),
      Success<Student?>(value: final Student existing) =>
        await _applyStudentUpdate(existing, student),
    };
  }

  Future<Result<Student>> _applyStudentUpdate(
    Student existing,
    Student incoming,
  ) async {
    final String newDedupeKey = _idGenerator.dedupeKey(<String>[
      existing.schoolId,
      incoming.studentName,
      incoming.grade,
      incoming.section,
      incoming.dateOfBirth?.toIso8601String() ?? '',
    ]);
    final DocumentReference<Map<String, dynamic>> studentRef = _firestore
        .collection(Collections.students)
        .doc(existing.studentId);

    if (newDedupeKey == existing.dedupeKey) {
      // No identity-affecting field changed: a plain update, no guard dance.
      final Result<void> write = await guardAsync(
        () => studentRef.update(<String, Object?>{
          'studentName': incoming.studentName,
          'gender': incoming.gender.wireName,
          'dateOfBirth': incoming.dateOfBirth?.toIso8601String(),
          'grade': incoming.grade,
          'section': incoming.section,
          'mediumOfInstruction': incoming.mediumOfInstruction,
          'language': incoming.language,
          'electiveSubject': incoming.electiveSubject,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        onError: mapFirestoreError,
      );
      return write.fold(
        onSuccess: (_) => ok(existing.copyWith(
          studentName: incoming.studentName,
          gender: incoming.gender,
          dateOfBirth: incoming.dateOfBirth,
          mediumOfInstruction: incoming.mediumOfInstruction,
          language: incoming.language,
          electiveSubject: incoming.electiveSubject,
        )),
        onFailure: err,
      );
    }

    final DocumentReference<Map<String, dynamic>> oldDedupeRef = _firestore
        .collection(Collections.studentDedupe)
        .doc(existing.dedupeKey);
    final DocumentReference<Map<String, dynamic>> newDedupeRef = _firestore
        .collection(Collections.studentDedupe)
        .doc(newDedupeKey);

    final Result<_TransactionOutcome> outcome = await guardAsync(
      () => _firestore.runTransaction<_TransactionOutcome>((
        Transaction transaction,
      ) async {
        final DocumentSnapshot<Map<String, dynamic>> guard = await transaction
            .get(newDedupeRef);
        if (guard.exists) {
          return _TransactionOutcome.duplicate(
            guard.data()?['studentId'] as String? ?? '',
          );
        }
        transaction.delete(oldDedupeRef);
        transaction.set(newDedupeRef, <String, Object?>{
          'studentId': existing.studentId,
          'schoolId': existing.schoolId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(studentRef, <String, Object?>{
          'studentName': incoming.studentName,
          'gender': incoming.gender.wireName,
          'dateOfBirth': incoming.dateOfBirth?.toIso8601String(),
          'grade': incoming.grade,
          'section': incoming.section,
          'mediumOfInstruction': incoming.mediumOfInstruction,
          'language': incoming.language,
          'electiveSubject': incoming.electiveSubject,
          'dedupeKey': newDedupeKey,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return const _TransactionOutcome.created();
      }),
      onError: mapFirestoreError,
    );

    return switch (outcome) {
      FailureResult<_TransactionOutcome>(:final failure) => err(failure),
      Success<_TransactionOutcome>(value: _Created()) => ok(
        existing.copyWith(
          studentName: incoming.studentName,
          gender: incoming.gender,
          dateOfBirth: incoming.dateOfBirth,
          grade: incoming.grade,
          section: incoming.section,
          mediumOfInstruction: incoming.mediumOfInstruction,
          language: incoming.language,
          electiveSubject: incoming.electiveSubject,
          dedupeKey: newDedupeKey,
        ),
      ),
      Success<_TransactionOutcome>(
        value: _Duplicate(:final existingStudentId),
      ) =>
        await _duplicateFailure(existingStudentId),
    };
  }

  @override
  Future<Result<Student>> setStudentActive(
    String studentId,
    bool activeStatus,
  ) async {
    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection(Collections.students)
        .doc(studentId);
    final Result<void> write = await guardAsync(
      () => ref.update(<String, Object?>{
        'activeStatus': activeStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      onError: mapFirestoreError,
    );
    if (write.isFailure) {
      return err(write.failureOrNull!);
    }
    final Result<Student?> reread = await getStudent(
      studentId,
      scope: const AccessScope.global(),
    );
    return reread.flatMap(
      (Student? student) => student == null
          ? err(
              NotFoundFailure(
                userMessage: 'That student could not be found.',
                entityType: 'student',
                entityId: studentId,
              ),
            )
          : ok(student),
    );
  }

  @override
  Future<Result<StudentImportReport>> importStudents({
    required String schoolId,
    required List<StudentImportRow> rows,
  }) async {
    // Sequential, not batched: each row needs its own dedupe transaction, and
    // running them one at a time is what lets row 41 fail without touching
    // rows 1-40 — a partial import is exactly the intended outcome when some
    // rows are duplicates (requirement section 11), not a failure to recover
    // from.
    int createdCount = 0;
    final List<StudentImportRejection> rejections = <StudentImportRejection>[];
    for (final StudentImportRow row in rows) {
      final Result<Student> result = await createStudent(
        schoolId: schoolId,
        studentName: row.studentName,
        gender: Gender.fromWireName(row.gender?.toUpperCase()),
        grade: row.grade,
        section: row.section,
        mediumOfInstruction: row.mediumOfInstruction ?? '',
        language: row.language ?? '',
        dateOfBirth: row.dateOfBirth,
        electiveSubject: row.electiveSubject,
        externalStudentCode: row.externalStudentCode,
      );
      switch (result) {
        case Success<Student>():
          createdCount++;
        case FailureResult<Student>(:final failure):
          rejections.add(
            StudentImportRejection(
              rowNumber: row.rowNumber,
              studentName: row.studentName,
              reason: failure is DuplicateFailure
                  ? ImportRejectionReason.duplicate
                  : ImportRejectionReason.other,
              detail: failure.userMessage,
            ),
          );
      }
    }
    return ok(
      StudentImportReport(
        totalRows: rows.length,
        createdCount: createdCount,
        parseErrors: const <StudentImportParseError>[],
        rejections: rejections,
      ),
    );
  }

  // -------------------------------------------------------------- helpers

  Page<Student> _pageFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int limit,
    AccessScope scope,
  ) {
    final List<Student> items = <Student>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final Map<String, Object?> json = firestoreDocToJson(
        doc.data().cast<String, Object?>(),
      );
      final Student? student = Student.tryFromJson(json);
      // A query already filtered by schoolId, but scope is re-checked here
      // too: a Supervisor scoped to specific grade-sections needs that finer
      // cut applied client-side, since Firestore cannot express "any of these
      // grade-section pairs" as a single query clause.
      if (student != null &&
          scope.covers(
            ScopeTarget(
              stateId: student.stateId,
              districtId: student.districtId,
              clusterId: student.clusterId,
              schoolId: student.schoolId,
              grade: student.grade,
              section: student.section,
            ),
          )) {
        items.add(student);
      }
    }
    final bool hasMore = docs.length == limit && docs.isNotEmpty;
    String? nextCursor;
    if (hasMore) {
      final Map<String, Object?> lastJson = firestoreDocToJson(
        docs.last.data().cast<String, Object?>(),
      );
      nextCursor = FirestoreCursor(
        orderValue: lastJson['studentName'] as String? ?? '',
        documentId: docs.last.id,
      ).encode();
    }
    return Page<Student>(items: items, nextCursor: nextCursor);
  }
}

/// The result of the create/update transaction: either the write went
/// through, or an existing dedupe guard was found (naming the student that
/// already holds it).
///
/// Matched directly via `switch` at each call site rather than through a
/// callback-based `when`: one branch's follow-up (`_duplicateFailure`) is
/// asynchronous and the other (`ok(student)`) is not, and a single generic
/// callback signature cannot express both without forcing one side to lie
/// about its type.
sealed class _TransactionOutcome {
  const _TransactionOutcome();

  const factory _TransactionOutcome.created() = _Created;
  const factory _TransactionOutcome.duplicate(String existingStudentId) =
      _Duplicate;
}

final class _Created extends _TransactionOutcome {
  const _Created();
}

final class _Duplicate extends _TransactionOutcome {
  const _Duplicate(this.existingStudentId);

  final String existingStudentId;
}
