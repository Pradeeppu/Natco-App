/// In-memory [AuthService].
///
/// This is not a stub for missing work — it is how demo mode and the widget
/// tests run the real application (real router, real guards, real controllers)
/// with no Firebase project, and how the six roles get exercised end to end
/// without provisioning six accounts (requirement section 53).
///
/// It holds no real student data and is never wired into a production build:
/// `AppEnvironment.prod` selects the Firebase implementation.
library;

import 'dart:async';

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/data/service/auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/schools/data/service/demo_master_data.dart';

/// A demo account: a profile plus the password that unlocks it.
final class DemoAccount {
  const DemoAccount({required this.user, required this.password});

  final AppUser user;
  final String password;
}

final class InMemoryAuthService implements AuthService {
  InMemoryAuthService({
    required List<DemoAccount> accounts,
    Clock clock = const SystemClock(),
    Duration latency = Duration.zero,
  }) : _accounts = <String, DemoAccount>{
         for (final DemoAccount account in accounts)
           account.user.email.toLowerCase(): account,
       },
       _clock = clock,
       _latency = latency;

  final Map<String, DemoAccount> _accounts;
  final Clock _clock;

  /// Simulated round-trip delay, so loading states are visible in demo mode
  /// and testable in widget tests.
  final Duration _latency;

  final StreamController<String?> _authState =
      StreamController<String?>.broadcast();

  AppUser? _signedIn;

  /// Every configured demo account, for the demo-mode login hints.
  List<DemoAccount> get accounts =>
      List<DemoAccount>.unmodifiable(_accounts.values);

  @override
  Future<Result<AppUser?>> currentUser() async {
    await _delay();
    return ok(_signedIn);
  }

  @override
  Future<Result<AppUser>> signIn({
    required String email,
    required String password,
  }) async {
    await _delay();
    final DemoAccount? account = _accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      return err(AuthFailure.invalidCredentials(diagnostic: 'demo mismatch'));
    }
    if (!account.user.isActive) {
      return err(AuthFailure.accountDisabled(diagnostic: 'demo inactive'));
    }
    final AppUser user = account.user.copyWith(lastLoginAt: _clock.nowUtc());
    _signedIn = user;
    _authState.add(user.userId);
    return ok(user);
  }

  @override
  Future<Result<void>> signOut() async {
    await _delay();
    _signedIn = null;
    _authState.add(null);
    return ok(null);
  }

  @override
  Future<Result<AppUser>> refreshUser(String userId) async {
    await _delay();
    final DemoAccount? account = _accounts.values
        .where((DemoAccount a) => a.user.userId == userId)
        .firstOrNull;
    if (account == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That account could not be found.',
          entityType: 'user',
          entityId: userId,
        ),
      );
    }
    if (!account.user.isActive) {
      return err(AuthFailure.accountDisabled(diagnostic: 'demo inactive'));
    }
    return ok(account.user);
  }

  @override
  Future<Result<void>> refreshCredentials() async {
    await _delay();
    return ok(null);
  }

  @override
  Future<Result<void>> sendPasswordReset(String email) async {
    await _delay();
    // Always succeeds, matching the production behaviour that refuses to
    // reveal whether an address exists.
    return ok(null);
  }

  @override
  Stream<String?> authStateChanges() => _authState.stream;

  Future<void> _delay() => _latency == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(_latency);

  Future<void> dispose() => _authState.close();
}

/// The demo accounts, one per role (requirement section 53).
///
/// Passwords are visible on purpose: these accounts exist only in builds with
/// no backend, and hiding them would make demo mode unusable without adding
/// any security. They are never created in a real Firebase project.
List<DemoAccount> buildDemoAccounts() {
  const String password = 'natco1234';
  const AccessScope stateScope = AccessScope(
    level: ScopeLevel.state,
    stateIds: <String>{DemoHierarchyIds.stateId},
  );
  const AccessScope clusterScope = AccessScope(
    level: ScopeLevel.cluster,
    stateIds: <String>{DemoHierarchyIds.stateId},
    districtIds: <String>{DemoHierarchyIds.districtId1},
    clusterIds: <String>{DemoHierarchyIds.clusterId1, DemoHierarchyIds.clusterId2},
  );
  // School-level scopes carry their cluster, district and state alongside
  // their schools, exactly as `UserRepositoryImpl._resolveScope` writes them.
  // This does not widen what the holder can reach — `AccessScope.covers` tests
  // a school-level scope through its enumerated schools only — but it is what
  // lets `AccessScope.isWithin` answer "does this person work inside my
  // clusters" without a lookup per row. Omit it and the demo Supervisor's
  // Users list is empty, because containment that cannot be proven is refused.
  final AccessScope teacherScope = AccessScope(
    level: ScopeLevel.school,
    stateIds: const <String>{DemoHierarchyIds.stateId},
    districtIds: const <String>{DemoHierarchyIds.districtId1},
    clusterIds: const <String>{DemoHierarchyIds.clusterId1},
    schoolIds: const <String>{DemoHierarchyIds.schoolId1},
    gradeSections: <GradeSection>{const GradeSection(grade: '5', section: 'A')},
  );
  const AccessScope operatorScope = AccessScope(
    level: ScopeLevel.school,
    stateIds: <String>{DemoHierarchyIds.stateId},
    districtIds: <String>{DemoHierarchyIds.districtId1},
    clusterIds: <String>{DemoHierarchyIds.clusterId1},
    schoolIds: <String>{DemoHierarchyIds.schoolId1, DemoHierarchyIds.schoolId2},
  );

  return <DemoAccount>[
    const DemoAccount(
      user: AppUser(
        userId: 'demo_super_admin',
        email: 'superadmin@natco.demo',
        displayName: 'Asha Menon',
        role: UserRole.superAdmin,
        scope: AccessScope.global(),
        isActive: true,
      ),
      password: password,
    ),
    const DemoAccount(
      user: AppUser(
        userId: 'demo_assessment_admin',
        email: 'assessmentadmin@natco.demo',
        displayName: 'Rahul Iyer',
        role: UserRole.assessmentAdmin,
        scope: stateScope,
        isActive: true,
      ),
      password: password,
    ),
    const DemoAccount(
      user: AppUser(
        userId: 'demo_supervisor',
        email: 'supervisor@natco.demo',
        displayName: 'Fatima Sheikh',
        role: UserRole.supervisor,
        scope: clusterScope,
        isActive: true,
      ),
      password: password,
    ),
    DemoAccount(
      user: AppUser(
        userId: 'demo_teacher',
        email: 'teacher@natco.demo',
        displayName: 'Suresh Babu',
        role: UserRole.pstTeacher,
        scope: teacherScope,
        isActive: true,
      ),
      password: password,
    ),
    const DemoAccount(
      user: AppUser(
        userId: 'demo_scanner_operator',
        email: 'scanner@natco.demo',
        displayName: 'Nisha Rao',
        role: UserRole.scannerOperator,
        scope: operatorScope,
        isActive: true,
      ),
      password: password,
    ),
    const DemoAccount(
      user: AppUser(
        userId: 'demo_viewer',
        email: 'viewer@natco.demo',
        displayName: 'Vikram Desai',
        role: UserRole.viewer,
        scope: stateScope,
        isActive: true,
      ),
      password: password,
    ),
  ];
}
