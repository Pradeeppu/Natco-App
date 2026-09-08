/// End-to-end tests for the workflows phase 1 delivers.
///
/// These drive the whole app — real router, real guards, real controllers,
/// real repository — over in-memory services, and they exercise sequences a
/// single-screen test cannot: a deep link surviving a sign-in, a session
/// surviving an app restart with no network, and a role revoked while the
/// device was offline taking effect on reconnect.
///
/// On-device integration tests (`integration_test/`) arrive with phase 5, when
/// there is a camera to drive. Until then these run on CI with no device,
/// which is what keeps them run rather than intended.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/app/config/app_environment.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/route_guard.dart';
import 'package:natco_app/app/router.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/features/auth/data/service/in_memory_auth_service.dart';
import 'package:natco_app/features/auth/data/store/session_store.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

const String _password = 'natco1234';
const String _teacherEmail = 'teacher@natco.test';

AppUser _teacher({UserRole role = UserRole.pstTeacher, bool isActive = true}) =>
    AppUser(
      userId: 'u_teacher',
      email: _teacherEmail,
      displayName: 'Suresh Babu',
      role: role,
      scope: AccessScope.singleSchool('sch1'),
      isActive: isActive,
    );

/// Holds the pieces that must survive an "app restart" within a test.
final class _World {
  _World({required this.accounts})
    : sessionStore = InMemorySessionStore(),
      auditSink = InMemoryAuditSink(),
      clock = FixedClock(DateTime.utc(2026, 9, 8, 9)),
      connectivity = FakeConnectivityService();

  /// Mutable so a test can change a user's role or active state, as an
  /// administrator would on the server.
  List<DemoAccount> accounts;

  /// Shared across restarts: this is the device's storage, not the app's
  /// memory.
  final InMemorySessionStore sessionStore;
  final InMemoryAuditSink auditSink;
  final FixedClock clock;
  final FakeConnectivityService connectivity;

  ProviderContainer? _container;

  ProviderContainer get container => _container!;

  /// Launches (or relaunches) the app against the same device storage.
  Future<ProviderContainer> launch(WidgetTester tester) async {
    _container?.dispose();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.forEnvironment(AppEnvironment.demo)
              .copyWith(offlineSessionValidity: const Duration(days: 7)),
        ),
        clockProvider.overrideWithValue(clock),
        deviceInfoProvider.overrideWithValue(
          const StaticDeviceInfoService(deviceId: 'field-device-1'),
        ),
        connectivityProvider.overrideWithValue(connectivity),
        sessionStoreProvider.overrideWithValue(sessionStore),
        auditSinkProvider.overrideWithValue(auditSink),
        authServiceProvider.overrideWith(
          (Ref ref) => InMemoryAuthService(accounts: accounts, clock: clock),
        ),
      ],
    );
    _container = container;
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _App(container: container),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  String get location => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  SessionState get session => container.read(sessionProvider);
}

final class _App extends ConsumerWidget {
  const _App({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    theme: NatcoTheme.light(),
    routerConfig: ref.watch(routerProvider),
  );
}

Future<void> _signInThroughTheForm(
  WidgetTester tester, {
  String email = _teacherEmail,
  String password = _password,
}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email address'),
    email,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    password,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  group('sign-in workflow', () {
    testWidgets('a first launch lands on login and reaches the dashboard', (
      WidgetTester tester,
    ) async {
      final _World world = _World(
        accounts: <DemoAccount>[
          DemoAccount(user: _teacher(), password: _password),
        ],
      );
      await world.launch(tester);

      expect(world.location, RoutePaths.login);

      await _signInThroughTheForm(tester);

      expect(world.location, RoutePaths.dashboard);
      expect(find.text('Suresh'), findsOneWidget);
      expect(find.text('PST Teacher'), findsOneWidget);
      // The sign-in is audited with the role that was in force.
      expect(
        world.auditSink.events.map((AuditEvent e) => e.action),
        contains(AuditAction.loginSucceeded),
      );
      expect(world.auditSink.events.last.deviceId, 'field-device-1');
    });

    testWidgets('a deep link survives the sign-in it triggered', (
      WidgetTester tester,
    ) async {
      final _World world = _World(
        accounts: <DemoAccount>[
          DemoAccount(user: _teacher(), password: _password),
        ],
      );
      await world.launch(tester);

      // As a notification or a shared link would.
      world.container.read(routerProvider).go(RoutePaths.omrCapture);
      await tester.pumpAndSettle();
      expect(world.location, RoutePaths.login);

      await _signInThroughTheForm(tester);

      expect(
        world.location,
        RoutePaths.omrCapture,
        reason: 'the user should arrive where they were heading',
      );
    });
  });

  group('offline workflow', () {
    testWidgets('a session survives an app restart with no network', (
      WidgetTester tester,
    ) async {
      // Requirement section 23 and Critical Rule 8: the field workflow must
      // not depend on a connection.
      final _World world = _World(
        accounts: <DemoAccount>[
          DemoAccount(user: _teacher(), password: _password),
        ],
      );
      await world.launch(tester);
      await _signInThroughTheForm(tester);
      expect(world.location, RoutePaths.dashboard);

      // The teacher walks into a school with no signal, and the app is killed.
      world.connectivity.emit(ConnectionStatus.offline);
      world.clock.advance(const Duration(hours: 20));
      await world.launch(tester);

      expect(world.location, RoutePaths.dashboard);
      expect((world.session as SessionAuthenticated).isOffline, isTrue);
      expect(
        find.textContaining('Working from your saved session'),
        findsOneWidget,
      );
      expect(
        find.text('Offline. Your work is saved on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('an expired offline session requires a fresh sign-in', (
      WidgetTester tester,
    ) async {
      final _World world = _World(
        accounts: <DemoAccount>[
          DemoAccount(user: _teacher(), password: _password),
        ],
      );
      await world.launch(tester);
      await _signInThroughTheForm(tester);

      world.connectivity.emit(ConnectionStatus.offline);
      world.clock.advance(const Duration(days: 8));
      await world.launch(tester);

      expect(world.location, RoutePaths.login);
      expect(
        find.textContaining('Your offline session has expired'),
        findsOneWidget,
      );
    });

    testWidgets('a role granted while offline takes effect on reconnect', (
      WidgetTester tester,
    ) async {
      final _World world = _World(
        accounts: <DemoAccount>[
          DemoAccount(user: _teacher(), password: _password),
        ],
      );
      await world.launch(tester);
      await _signInThroughTheForm(tester);

      // As a teacher, the validation queue is refused.
      world.container.read(routerProvider).go(RoutePaths.omrValidationQueue);
      await tester.pumpAndSettle();
      expect(world.location, RoutePaths.unauthorized);

      // An administrator promotes them while the device is offline.
      world.connectivity.emit(ConnectionStatus.offline);
      world.accounts = <DemoAccount>[
        DemoAccount(
          user: _teacher(role: UserRole.supervisor),
          password: _password,
        ),
      ];
      await world.launch(tester);
      // Still the cached role: nothing has been able to tell the device.
      expect(
        (world.session as SessionAuthenticated).session.user.role,
        UserRole.pstTeacher,
      );

      // Reconnecting revalidates.
      world.connectivity.emit(ConnectionStatus.onlineUnmetered);
      await world.container.read(sessionProvider.notifier).revalidate();
      await tester.pumpAndSettle();

      expect(
        (world.session as SessionAuthenticated).session.user.role,
        UserRole.supervisor,
      );
      world.container.read(routerProvider).go(RoutePaths.omrValidationQueue);
      await tester.pumpAndSettle();
      expect(world.location, RoutePaths.omrValidationQueue);
    });

    testWidgets('a deactivation while offline ends the session on reconnect', (
      WidgetTester tester,
    ) async {
      final _World world = _World(
        accounts: <DemoAccount>[
          DemoAccount(user: _teacher(), password: _password),
        ],
      );
      await world.launch(tester);
      await _signInThroughTheForm(tester);

      // An administrator deactivates the account while the device is offline.
      world.accounts = <DemoAccount>[
        DemoAccount(user: _teacher(isActive: false), password: _password),
      ];
      world.connectivity.emit(ConnectionStatus.offline);
      await world.launch(tester);
      expect(
        world.location,
        RoutePaths.dashboard,
        reason: 'the cached session still works offline',
      );

      // The device reconnects.
      world.connectivity.emit(ConnectionStatus.onlineUnmetered);
      await world.container.read(sessionProvider.notifier).revalidate();
      await tester.pumpAndSettle();

      expect(world.location, RoutePaths.login);
      expect(
        find.textContaining('This account has been deactivated'),
        findsOneWidget,
      );
      expect(
        (await world.sessionStore.read()).valueOrNull,
        isNull,
        reason: 'a deactivated account must not leave a reusable session',
      );
    });
  });

  group('role restriction workflow', () {
    testWidgets('each role sees only its own screens across a full session', (
      WidgetTester tester,
    ) async {
      final List<DemoAccount> accounts = UserRole.values
          .map(
            (UserRole role) => DemoAccount(
              user: AppUser(
                userId: 'u_${role.name}',
                email: '${role.name}@natco.test',
                displayName: 'Test ${role.displayName}',
                role: role,
                scope: const AccessScope.global(),
                isActive: true,
              ),
              password: _password,
            ),
          )
          .toList(growable: false);

      for (final UserRole role in UserRole.values) {
        final _World world = _World(accounts: accounts);
        await world.launch(tester);
        await _signInThroughTheForm(tester, email: '${role.name}@natco.test');
        expect(world.location, RoutePaths.dashboard);

        for (final String path in <String>[
          RoutePaths.omrCapture,
          RoutePaths.omrValidationQueue,
          RoutePaths.analytics,
          RoutePaths.reports,
          RoutePaths.calibration,
          RoutePaths.students,
          RoutePaths.settings,
        ]) {
          world.container.read(routerProvider).go(path);
          await tester.pumpAndSettle();

          // The expected outcome comes from the permission matrix itself, so
          // this test cannot drift away from it.
          final RouteAccessRule rule = ruleForMatchedPath(path)!;
          final bool shouldReach = switch (rule.access) {
            RouteAccess.public || RouteAccess.authenticated => true,
            RouteAccess.permission => role.can(rule.permission!),
          };

          expect(
            world.location,
            shouldReach ? path : RoutePaths.unauthorized,
            reason: '${role.wireName} at $path landed on ${world.location}',
          );
        }

        await world.container.read(sessionProvider.notifier).signOut();
        await tester.pumpAndSettle();
        expect(world.location, RoutePaths.login);
      }
    });
  });

  group('sign-out workflow', () {
    testWidgets('clears the device session and is audited', (
      WidgetTester tester,
    ) async {
      final _World world = _World(
        accounts: <DemoAccount>[
          DemoAccount(user: _teacher(), password: _password),
        ],
      );
      await world.launch(tester);
      await _signInThroughTheForm(tester);

      world.container.read(routerProvider).go(RoutePaths.settings);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(world.location, RoutePaths.login);
      expect((await world.sessionStore.read()).valueOrNull, isNull);
      expect(
        world.auditSink.events.map((AuditEvent e) => e.action),
        contains(AuditAction.logout),
      );

      // A relaunch does not resurrect the session.
      await world.launch(tester);
      expect(world.location, RoutePaths.login);
    });
  });
}
