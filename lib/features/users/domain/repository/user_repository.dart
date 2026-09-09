/// User accounts (requirement §9).
///
/// Follows `SchoolHierarchyRepository`'s conventions: `list*` takes the
/// caller's own [AccessScope] so the filter is applied in the query rather
/// than after pagination, and mutations take `actorUserId`/`actorRole` because
/// the repository is a long-lived singleton with no concept of "the current
/// user".
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/users/domain/entity/user_draft.dart';

abstract interface class UserRepository {
  /// Users [scope] can see. A Supervisor sees the people working in their own
  /// clusters, not the whole programme.
  Future<Result<Page<AppUser>>> listUsers({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<AppUser>> getUser(String userId);

  /// Creates an account.
  ///
  /// The caller must have already run `UserProvisioningPolicy.checkDraft`;
  /// this method runs it again with the ancestry it resolves itself, because
  /// a check performed only by the caller is a check an attacker skips.
  ///
  /// In demo mode the account is usable immediately. Against Firebase the
  /// account document is written here and the Auth user plus custom claims are
  /// created by a Cloud Function watching that document — the app cannot mint
  /// an Auth user itself without holding admin credentials, and Critical
  /// Rule 3 forbids shipping those in the APK.
  Future<Result<AppUser>> createUser(
    UserDraft draft, {
    required AppUser actor,
  });

  /// Updates an existing account's name, phone, role, scope or active flag.
  Future<Result<AppUser>> updateUser(
    AppUser user, {
    required AppUser actor,
  });

  /// Deactivates rather than deletes.
  ///
  /// A deleted user would orphan every audit entry, captured sheet and score
  /// correction that names them, and the audit trail has to stay answerable
  /// (requirement §26).
  Future<Result<AppUser>> setUserActive(
    String userId, {
    required bool isActive,
    required AppUser actor,
  });
}
