/// The single [UserRepository] implementation.
///
/// Composes a swappable [UserDataSource] with provisioning policy, ancestry
/// denormalisation and audit logging — written once here rather than per
/// backend, mirroring `StudentRepositoryImpl`.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/repository/school_hierarchy_repository.dart';
import 'package:natco_app/features/users/data/service/user_data_source.dart';
import 'package:natco_app/features/users/domain/entity/user_draft.dart';
import 'package:natco_app/features/users/domain/repository/user_repository.dart';
import 'package:natco_app/features/users/domain/service/user_provisioning_policy.dart';

final class UserRepositoryImpl implements UserRepository {
  UserRepositoryImpl({
    required UserDataSource dataSource,
    required SchoolHierarchyRepository schoolRepository,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _dataSource = dataSource,
       _schoolRepository = schoolRepository,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final UserDataSource _dataSource;
  final SchoolHierarchyRepository _schoolRepository;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<Page<AppUser>>> listUsers({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listUsers(
    scope: scope,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<AppUser>> getUser(String userId) => _dataSource.getUser(userId);

  @override
  Future<Result<AppUser>> createUser(
    UserDraft draft, {
    required AppUser actor,
  }) async {
    final Result<_ResolvedScope> resolved = await _resolveScope(draft.scope);
    if (resolved.isFailure) {
      return err(resolved.failureOrNull!);
    }
    final _ResolvedScope scope = resolved.valueOrNull!;

    // Re-run the policy here, against ancestry this layer resolved itself.
    // The form ran it too, for immediate feedback — but a check that only the
    // form performs is a check that anything bypassing the form skips.
    final Failure? denial = UserProvisioningPolicy.checkDraft(
      actor: actor,
      draft: draft,
      resolvedSchoolTargets: scope.targets,
    );
    if (denial != null) {
      return err(denial);
    }

    final AppUser user = AppUser(
      userId: _idGenerator.newId(),
      email: draft.normalisedEmail,
      displayName: draft.displayName.trim(),
      phone: draft.phone,
      role: draft.role,
      scope: scope.denormalised,
      isActive: true,
    );

    final Result<AppUser> result = await _dataSource.createUser(user);
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.userCreated,
          entityId: user.userId,
          actor: actor,
          // Role and scope shape only. No email, no name — an audit entry is
          // read far more widely than the record it describes (§35).
          newValue: <String, Object?>{
            'role': user.role.wireName,
            'scopeLevel': user.scope.level.wireName,
            'schoolCount': user.scope.schoolIds.length,
          },
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<AppUser>> updateUser(
    AppUser user, {
    required AppUser actor,
  }) async {
    final Result<AppUser> currentResult = await _dataSource.getUser(user.userId);
    if (currentResult.isFailure) {
      return err(currentResult.failureOrNull!);
    }
    final AppUser current = currentResult.valueOrNull!;

    // Editing an account requires the right to have created it in the first
    // place — both as it is now and as it would become. Checking only the new
    // state would let a Supervisor take over an account that is currently a
    // Super Admin's; checking only the old would let them promote a teacher.
    final Failure? denialOnCurrent = UserProvisioningPolicy.checkRoleGrant(
      actor: actor,
      role: current.role,
    );
    if (denialOnCurrent != null) {
      return err(denialOnCurrent);
    }

    final Result<_ResolvedScope> resolved = await _resolveScope(user.scope);
    if (resolved.isFailure) {
      return err(resolved.failureOrNull!);
    }
    final _ResolvedScope scope = resolved.valueOrNull!;
    final Failure? denial = UserProvisioningPolicy.checkRoleGrant(
          actor: actor,
          role: user.role,
        ) ??
        UserProvisioningPolicy.checkScopeGrant(
          actor: actor,
          granted: user.scope,
          resolvedSchoolTargets: scope.targets,
        );
    if (denial != null) {
      return err(denial);
    }

    final Result<AppUser> result = await _dataSource.updateUser(
      user.copyWith(scope: scope.denormalised),
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          current.role == user.role
              ? AuditAction.userUpdated
              : AuditAction.userRoleChanged,
          entityId: user.userId,
          actor: actor,
          oldValue: <String, Object?>{
            'role': current.role.wireName,
            'scopeLevel': current.scope.level.wireName,
            'isActive': current.isActive,
          },
          newValue: <String, Object?>{
            'role': user.role.wireName,
            'scopeLevel': user.scope.level.wireName,
            'isActive': user.isActive,
          },
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<AppUser>> setUserActive(
    String userId, {
    required bool isActive,
    required AppUser actor,
  }) async {
    if (userId == actor.userId && !isActive) {
      // Locking yourself out is never the intent, and recovering from it needs
      // someone else with `manageUsers` — which, for the only Super Admin,
      // means nobody.
      return err(
        const ValidationFailure(
          userMessage: 'You cannot deactivate your own account.',
          diagnostic: 'self-deactivation attempt',
        ),
      );
    }
    final Result<AppUser> currentResult = await _dataSource.getUser(userId);
    if (currentResult.isFailure) {
      return err(currentResult.failureOrNull!);
    }
    final AppUser current = currentResult.valueOrNull!;
    final Failure? denial = UserProvisioningPolicy.checkRoleGrant(
      actor: actor,
      role: current.role,
    );
    if (denial != null) {
      return err(denial);
    }
    if (!current.scope.isWithin(actor.scope)) {
      return err(
        PermissionFailure.outOfScope(
          diagnostic: 'deactivation target outside actor scope',
        ),
      );
    }

    final Result<AppUser> result = await _dataSource.updateUser(
      current.copyWith(isActive: isActive),
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          isActive ? AuditAction.userReactivated : AuditAction.userDeactivated,
          entityId: userId,
          actor: actor,
          oldValue: <String, Object?>{'isActive': current.isActive},
          newValue: <String, Object?>{'isActive': isActive},
        ),
      );
    }
    return result;
  }

  /// Looks each school in [granted] up, so the policy can test containment
  /// against real ancestry, and returns the scope with that ancestry
  /// denormalised onto it.
  ///
  /// The denormalisation is what later lets a Supervisor list "people who work
  /// in my clusters" as one indexed query instead of a lookup per row, and it
  /// is what makes [AccessScope.isWithin] answerable at all. It does not widen
  /// the new user's own reach: [AccessScope.covers] tests a school-level scope
  /// through its enumerated schools only, so the extra cluster/district/state
  /// ids it carries are evidence about *where* those schools sit, not
  /// additional access.
  Future<Result<_ResolvedScope>> _resolveScope(AccessScope granted) async {
    if (granted.schoolIds.isEmpty) {
      return ok(_ResolvedScope(denormalised: granted, targets: const []));
    }
    final List<ScopeTarget> targets = <ScopeTarget>[];
    final Set<String> stateIds = <String>{...granted.stateIds};
    final Set<String> districtIds = <String>{...granted.districtIds};
    final Set<String> clusterIds = <String>{...granted.clusterIds};

    for (final String schoolId in granted.schoolIds) {
      final Result<School> result = await _schoolRepository.getSchool(schoolId);
      if (result.isFailure) {
        // Refuse rather than continue. A school we cannot read is a school we
        // cannot prove the actor owns, and the policy treats an unresolved
        // school as a denial for exactly that reason.
        return err(result.failureOrNull!);
      }
      final School school = result.valueOrNull!;
      targets.add(
        ScopeTarget(
          stateId: school.stateId,
          districtId: school.districtId,
          clusterId: school.clusterId,
          schoolId: school.schoolId,
        ),
      );
      stateIds.add(school.stateId);
      districtIds.add(school.districtId);
      clusterIds.add(school.clusterId);
    }

    return ok(
      _ResolvedScope(
        denormalised: granted.copyWith(
          stateIds: stateIds,
          districtIds: districtIds,
          clusterIds: clusterIds,
        ),
        targets: targets,
      ),
    );
  }

  AuditEvent _event(
    AuditAction action, {
    required String entityId,
    required AppUser actor,
    Map<String, Object?>? oldValue,
    Map<String, Object?>? newValue,
  }) => AuditEvent(
    auditId: _idGenerator.newId(),
    userId: actor.userId,
    role: actor.role.wireName,
    action: action,
    entityType: 'user',
    entityId: entityId,
    timestamp: _clock.nowUtc(),
    deviceId: _deviceInfo.deviceId,
    appVersion: _deviceInfo.appVersion,
    oldValue: oldValue,
    newValue: newValue,
  );
}

/// A granted scope plus the ancestry needed to authorise it.
final class _ResolvedScope {
  const _ResolvedScope({required this.denormalised, required this.targets});

  final AccessScope denormalised;
  final List<ScopeTarget> targets;
}
