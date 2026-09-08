/// One-shot lookup of a single student, for the detail screen. Same shape as
/// `schoolDetailProvider` — see that file's doc comment for why this is a
/// `FutureProvider.family` rather than a hand-written `Notifier`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

final class StudentDetailFailure implements Exception {
  const StudentDetailFailure(this.failure);

  final Failure failure;
}

final studentDetailProvider = FutureProvider.family<Student?, String>((
  Ref ref,
  String studentId,
) async {
  final AccessScope scope =
      ref.watch(sessionProvider).authorization.user?.scope ??
      const AccessScope(level: ScopeLevel.school);
  final Result<Student?> result = await ref
      .watch(studentsRepositoryProvider)
      .getStudent(studentId, scope: scope);
  return switch (result) {
    Success<Student?>(:final value) => value,
    FailureResult<Student?>(:final failure) => throw StudentDetailFailure(
      failure,
    ),
  };
});
