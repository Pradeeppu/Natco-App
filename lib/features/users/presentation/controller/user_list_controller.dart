/// Paginated, searchable, scope-filtered user list.
///
/// A Supervisor sees the people working in their own clusters; a Super Admin
/// sees everyone. The filtering happens in the query rather than afterwards,
/// for the reason `SchoolHierarchyRepository` documents: a page capped at 25
/// rows and filtered after the fact can return fewer than 25, or none, while
/// more exist.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/users/domain/repository/user_repository.dart';

final class UserListController extends PagedListController<AppUser> {
  @override
  Future<Result<Page<AppUser>>> fetchPage({
    required String query,
    required Object? cursor,
  }) {
    final UserRepository repository = ref.read(userRepositoryProvider);
    return repository.listUsers(
      scope: _scope(),
      query: query,
      cursor: cursor,
    );
  }

  /// Falls back to an empty school-level scope, which reaches nothing.
  /// A missing session must never read as "global" — see
  /// `SchoolListController._scope`.
  AccessScope _scope() {
    final SessionState session = ref.read(sessionProvider);
    return session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
  }
}

final AsyncNotifierProvider<UserListController, PagedListState<AppUser>>
userListControllerProvider =
    AsyncNotifierProvider<UserListController, PagedListState<AppUser>>(
      UserListController.new,
    );

/// One user, for the detail screen.
///
/// The type is inferred rather than written out: Riverpod 3 does not export
/// its family provider types from `package:flutter_riverpod`, so naming one
/// here would not compile — the same reason `hierarchy_providers.dart` gives.
final userProvider =
    FutureProvider.family<AppUser, String>((Ref ref, String userId) async {
      final Result<AppUser> result = await ref
          .read(userRepositoryProvider)
          .getUser(userId);
      return switch (result) {
        Success<AppUser>(:final AppUser value) => value,
        // Thrown so the screen's `AsyncValue.error` branch renders
        // `FailureView`; `asFailure` recovers the typed failure on the way out.
        FailureResult<AppUser>(:final failure) => throw failure,
      };
    });
