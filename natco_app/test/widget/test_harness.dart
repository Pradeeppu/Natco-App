/// Shared scaffolding for widget tests.
///
/// Tests run the *real* application wiring — the real router, the real guards,
/// the real controllers — against in-memory services. That is deliberate: a
/// widget test that stubs the router proves nothing about whether a teacher
/// can reach the validation queue.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/app/config/app_environment.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/router.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

/// A demo password shared by the test accounts.
const String kTestPassword = 'natco1234';

/// Builds a demo account for [role].
DemoAccount testAccount(
  UserRole role, {
  AccessScope? scope,
  bool isActive = true,
}) => DemoAccount(
  user: AppUser(
    userId: 'u_${role.wireName.toLowerCase()}',
    email: '${role.name}@natco.test',
    displayName: 'Test ${role.displayName}',
    role: role,
    scope: scope ?? const AccessScope.global(),
    isActive: isActive,
  ),
  password: kTestPassword,
);

/// Pumps the app with in-memory services.
///
/// Returns the container so a test can drive the session directly when it
/// needs to start from a signed-in state.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  List<DemoAccount>? accounts,
  ConnectionStatus connection = ConnectionStatus.onlineUnmetered,
  Size surfaceSize = const Size(400, 900),
}) async {
  // Set the physical size *and* pin the device pixel ratio to 1, so
  // `surfaceSize` is the logical size the layout actually sees. Setting the
  // physical size alone leaves the harness's own pixel ratio in play and a
  // "phone-sized" surface can end up wide enough to render the tablet rail.
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final List<DemoAccount> demoAccounts =
      accounts ?? <DemoAccount>[testAccount(UserRole.pstTeacher)];

  final ProviderContainer container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig.forEnvironment(AppEnvironment.demo),
      ),
      clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 9, 8, 9))),
      deviceInfoProvider.overrideWithValue(
        const StaticDeviceInfoService(deviceId: 'test-device'),
      ),
      connectivityProvider.overrideWithValue(
        FakeConnectivityService(connection),
      ),
      demoAccountsProvider.overrideWithValue(demoAccounts),
      // No artificial latency: tests drive the pump loop themselves.
      authServiceProvider.overrideWith(
        (Ref ref) => InMemoryAuthService(
          accounts: demoAccounts,
          clock: ref.watch(clockProvider),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _TestApp(container: container),
    ),
  );
  // Settle the initial session restore.
  await tester.pumpAndSettle();
  return container;
}

/// Signs in through the repository, then settles the router.
Future<void> signInAs(
  WidgetTester tester,
  ProviderContainer container,
  UserRole role,
) async {
  await container
      .read(sessionProvider.notifier)
      .signIn(email: '${role.name}@natco.test', password: kTestPassword);
  await tester.pumpAndSettle();
}

/// Scrolls the nearest scrollable until [finder] is on screen.
///
/// The dashboard is a list, so content below the fold is not built until it is
/// scrolled to. A test that asserts on it has to scroll first, exactly as a
/// user would.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

final class _TestApp extends ConsumerWidget {
  const _TestApp({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    theme: NatcoTheme.light(),
    routerConfig: ref.watch(routerProvider),
  );
}
