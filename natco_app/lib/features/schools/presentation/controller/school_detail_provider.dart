/// One-shot lookup of a single school, for the detail screen.
///
/// A `FutureProvider.family` rather than a hand-written `Notifier`: Riverpod's
/// code-free `Notifier` has no family support in this version (see
/// `StudentsListController`'s doc comment for the full reasoning), but the
/// functional providers (`Provider`, `FutureProvider`, `StreamProvider`) kept
/// theirs — and a one-shot fetch with no further mutation is exactly what
/// `FutureProvider` is for.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

/// Thrown into the provider's `AsyncValue.error` so the screen can render a
/// [Failure] the same way every other screen does, via `FailureView`.
final class SchoolDetailFailure implements Exception {
  const SchoolDetailFailure(this.failure);

  final Failure failure;
}

final schoolDetailProvider = FutureProvider.family<School?, String>((
  Ref ref,
  String schoolId,
) async {
  final AccessScope scope =
      ref.watch(sessionProvider).authorization.user?.scope ??
      const AccessScope(level: ScopeLevel.school);
  final Result<School?> result = await ref
      .watch(schoolsRepositoryProvider)
      .getSchool(schoolId, scope: scope);
  return switch (result) {
    Success<School?>(:final value) => value,
    FailureResult<School?>(:final failure) => throw SchoolDetailFailure(
      failure,
    ),
  };
});
