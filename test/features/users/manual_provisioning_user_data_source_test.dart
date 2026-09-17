import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/users/data/service/manual_provisioning_user_data_source.dart';
import 'package:natco_app/features/users/data/service/user_data_source.dart';

final class _RecordingUserDataSource implements UserDataSource {
  bool createUserCalled = false;

  final AppUser stubUser = const AppUser(
    userId: 'u1',
    email: 'teacher@school.test',
    displayName: 'A Teacher',
    role: UserRole.pstTeacher,
    scope: AccessScope.global(),
    isActive: true,
  );

  @override
  Future<Result<AppUser>> createUser(AppUser user) async {
    createUserCalled = true;
    return ok(user);
  }

  @override
  Future<Result<AppUser>> getUser(String userId) async => ok(stubUser);

  @override
  Future<Result<Page<AppUser>>> listUsers({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async => ok((items: <AppUser>[stubUser], nextCursor: null, hasMore: false));

  @override
  Future<Result<AppUser>> updateUser(AppUser user) async => ok(user);
}

void main() {
  group('ManualProvisioningUserDataSource', () {
    test('createUser fails with a clear reason instead of reaching the delegate', () async {
      final _RecordingUserDataSource delegate = _RecordingUserDataSource();
      final ManualProvisioningUserDataSource dataSource =
          ManualProvisioningUserDataSource(delegate);

      final Result<AppUser> result = await dataSource.createUser(
        delegate.stubUser,
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ConfigurationFailure>());
      expect(
        delegate.createUserCalled,
        isFalse,
        reason:
            'the whole point is that a broken, unsignable-in account is '
            'never written',
      );
    });

    test('delegates every other operation unchanged', () async {
      final _RecordingUserDataSource delegate = _RecordingUserDataSource();
      final ManualProvisioningUserDataSource dataSource =
          ManualProvisioningUserDataSource(delegate);

      final Result<AppUser> got = await dataSource.getUser('u1');
      expect(got.valueOrNull, delegate.stubUser);

      final Result<Page<AppUser>> listed = await dataSource.listUsers(
        scope: const AccessScope.global(),
      );
      expect(listed.valueOrNull?.items, <AppUser>[delegate.stubUser]);

      final Result<AppUser> updated = await dataSource.updateUser(
        delegate.stubUser,
      );
      expect(updated.valueOrNull, delegate.stubUser);
    });
  });
}
