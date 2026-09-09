/// Backend-swappable raw storage for user accounts.
///
/// Mirrors `SchoolDataSource`/`StudentDataSource`: this layer does CRUD and
/// paged queries only. Policy, ancestry resolution and audit logging live once
/// in `UserRepositoryImpl` rather than being reimplemented per backend.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';

abstract interface class UserDataSource {
  Future<Result<Page<AppUser>>> listUsers({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<AppUser>> getUser(String userId);

  /// Creates the account, rejecting a duplicate email.
  ///
  /// Email uniqueness is a guard document (`user_email/{normalisedEmail}`)
  /// created in the same transaction as the user, the same pattern
  /// `student_dedupe` uses — two Supervisors onboarding the same teacher at
  /// once must produce one account and one named rejection, not two accounts
  /// that later disagree about that person's scope
  /// (docs/03-firestore-schema.md).
  Future<Result<AppUser>> createUser(AppUser user);

  Future<Result<AppUser>> updateUser(AppUser user);
}
