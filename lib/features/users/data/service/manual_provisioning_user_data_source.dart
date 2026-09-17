/// Wraps a [UserDataSource], refusing [createUser].
///
/// `FirestoreUserDataSource.createUser` writes only the Firestore profile
/// document — the matching Firebase Auth account and its custom claims were
/// meant to come from an `onUserWrite` Cloud Function watching that
/// collection. That function has never been built, and this project stays
/// on the Spark plan, which cannot run Cloud Functions at all. Left
/// unguarded, the in-app "Add User" screen would show a false success
/// ("X can now sign in") after creating a profile document nobody can ever
/// authenticate as.
///
/// Real accounts are created instead with
/// `firebase/scripts/bootstrap-admin/create-user.js`, which sets the Auth
/// account, custom claims and Firestore document together from a service
/// account. This decorator exists so that gap fails loudly and immediately,
/// not silently three steps later when the new hire can't log in.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/users/data/service/user_data_source.dart';

final class ManualProvisioningUserDataSource implements UserDataSource {
  const ManualProvisioningUserDataSource(this._delegate);

  final UserDataSource _delegate;

  @override
  Future<Result<AppUser>> createUser(AppUser user) async => err(
    const ConfigurationFailure(
      userMessage:
          'New accounts must be created by a Super Admin running the '
          'account-creation script — this build cannot create a working '
          'sign-in from here. Ask your Super Admin to run '
          'firebase/scripts/bootstrap-admin/create-user.js for this person.',
      diagnostic:
          'FirestoreUserDataSource.createUser cannot provision a Firebase '
          'Auth account or custom claims without onUserWrite, which is not '
          'deployed (Spark plan has no Cloud Functions).',
    ),
  );

  @override
  Future<Result<Page<AppUser>>> listUsers({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _delegate.listUsers(
    scope: scope,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<AppUser>> getUser(String userId) => _delegate.getUser(userId);

  @override
  Future<Result<AppUser>> updateUser(AppUser user) => _delegate.updateUser(user);
}
