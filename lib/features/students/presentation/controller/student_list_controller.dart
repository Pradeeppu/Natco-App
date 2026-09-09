/// Paginated, searchable, scope-filtered student list.
///
/// `setSchoolFilter` narrows the list to one school (the common case for a
/// teacher opening their own school, or an admin drilling in from a school
/// detail screen); left `null` it searches by name across the caller's
/// whole scope.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/repository/student_repository.dart';

final class StudentListController extends PagedListController<Student> {
  String? _schoolId;

  String? get schoolFilter => _schoolId;

  void setSchoolFilter(String? schoolId) {
    if (schoolId == _schoolId) {
      return;
    }
    _schoolId = schoolId;
    refresh();
  }

  @override
  Future<Result<Page<Student>>> fetchPage({
    required String query,
    required Object? cursor,
  }) {
    final AccessScope scope = _scope();
    final StudentRepository repository = ref.read(studentRepositoryProvider);
    return repository.listStudents(
      scope: scope,
      schoolId: _schoolId,
      query: query,
      cursor: cursor,
    );
  }

  /// See `SchoolListController._scope` for why the fallback denies rather
  /// than grants.
  AccessScope _scope() {
    final SessionState session = ref.read(sessionProvider);
    return session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
  }
}

final AsyncNotifierProvider<StudentListController, PagedListState<Student>>
studentListControllerProvider =
    AsyncNotifierProvider<StudentListController, PagedListState<Student>>(
      StudentListController.new,
    );

/// One student by id — for a results row or any other screen that has a
/// `studentId` and needs the name it belongs to, without pulling in the whole
/// paginated list. Type inferred, not written out: Riverpod 3 does not export
/// family provider types from `package:flutter_riverpod`, the same reason
/// `hierarchy_providers.dart` gives.
final studentProvider =
    FutureProvider.family<Student, String>((Ref ref, String studentId) async {
      final Result<Student> result = await ref
          .watch(studentRepositoryProvider)
          .getStudent(studentId);
      return switch (result) {
        Success<Student>(:final Student value) => value,
        FailureResult<Student>(:final failure) => throw failure,
      };
    });
