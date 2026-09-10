/// Declarative routing with role guards.
///
/// The route table is the single place where a screen's required permission is
/// declared. Because [GuardedRoute] makes that field mandatory, a new screen
/// cannot be added without deciding who may see it — and [RouteGuard] treats
/// anything it cannot find a rule for as forbidden, so a mistake fails closed
/// (docs/05-navigation-map.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/route_guard.dart';
import 'package:natco_app/app/shell.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/analytics/presentation/screen/analytics_screen.dart';
import 'package:natco_app/features/assessment_sessions/presentation/screen/assessment_session_screen.dart';
import 'package:natco_app/features/assessment_sessions/presentation/screen/sessions_screen.dart';
import 'package:natco_app/features/assessments/presentation/screen/answer_key_screen.dart';
import 'package:natco_app/features/assessments/presentation/screen/assessment_detail_screen.dart';
import 'package:natco_app/features/assessments/presentation/screen/assessments_screen.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/auth/presentation/screen/login_screen.dart';
import 'package:natco_app/features/auth/presentation/screen/splash_screen.dart';
import 'package:natco_app/features/auth/presentation/screen/unauthorized_screen.dart';
import 'package:natco_app/features/dashboard/presentation/screen/dashboard_screen.dart';
import 'package:natco_app/features/omr_capture/presentation/screen/omr_capture_screen.dart';
import 'package:natco_app/features/omr_processing/presentation/screen/omr_review_screen.dart';
import 'package:natco_app/features/omr_validation/presentation/screen/omr_validation_queue_screen.dart';
import 'package:natco_app/features/omr_validation/presentation/screen/omr_validation_screen.dart';
import 'package:natco_app/features/reports/presentation/screen/reports_screen.dart';
import 'package:natco_app/features/results/presentation/screen/results_screen.dart';
import 'package:natco_app/features/results/presentation/screen/student_result_screen.dart';
import 'package:natco_app/features/schools/presentation/screen/school_detail_screen.dart';
import 'package:natco_app/features/schools/presentation/screen/schools_screen.dart';
import 'package:natco_app/features/settings/presentation/screen/calibration_screen.dart';
import 'package:natco_app/features/settings/presentation/screen/settings_screen.dart';
import 'package:natco_app/features/students/presentation/screen/student_detail_screen.dart';
import 'package:natco_app/features/students/presentation/screen/students_screen.dart';
import 'package:natco_app/features/sync/presentation/screen/sync_screen.dart';

/// One route, with its access rule and whether it sits inside the shell.
final class GuardedRoute {
  const GuardedRoute({
    required this.path,
    required this.rule,
    required this.builder,
    this.insideShell = false,
  });

  final String path;

  /// Mandatory. This is what makes the guard's fail-closed default safe: there
  /// is no way to register a route without an access decision.
  final RouteAccessRule rule;

  final Widget Function(BuildContext context, GoRouterState state) builder;

  /// Whether the screen is wrapped in the navigation shell. Full-screen tasks
  /// — capture, validation, a live session — deliberately are not, so the
  /// user cannot wander off mid-task by tapping the bar.
  final bool insideShell;
}

/// The route table (requirement section 57).
final List<GuardedRoute> kAppRoutes = <GuardedRoute>[
  GuardedRoute(
    path: RoutePaths.splash,
    rule: const RouteAccessRule.public(),
    builder: (_, _) => const SplashScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.login,
    rule: const RouteAccessRule.public(),
    builder: (_, _) => const LoginScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.unauthorized,
    rule: const RouteAccessRule.authenticated(),
    builder: (_, _) => const UnauthorizedScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.dashboard,
    rule: const RouteAccessRule.requires(Permission.viewDashboard),
    insideShell: true,
    builder: (_, _) => const DashboardScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.schools,
    rule: const RouteAccessRule.requires(Permission.viewSchools),
    insideShell: true,
    builder: (_, _) => const SchoolsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.schoolDetail,
    rule: const RouteAccessRule.requires(Permission.viewSchools),
    insideShell: true,
    builder: (_, GoRouterState state) => SchoolDetailScreen(
      schoolId: state.pathParameters['schoolId']!,
    ),
  ),
  GuardedRoute(
    path: RoutePaths.students,
    rule: const RouteAccessRule.requires(Permission.viewStudents),
    insideShell: true,
    builder: (_, _) => const StudentsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.studentDetail,
    rule: const RouteAccessRule.requires(Permission.viewStudents),
    insideShell: true,
    builder: (_, GoRouterState state) => StudentDetailScreen(
      studentId: state.pathParameters['studentId']!,
    ),
  ),
  GuardedRoute(
    path: RoutePaths.assessments,
    rule: const RouteAccessRule.requires(Permission.viewAssessments),
    insideShell: true,
    builder: (_, _) => const AssessmentsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.assessmentDetail,
    rule: const RouteAccessRule.requires(Permission.viewAssessments),
    insideShell: true,
    builder: (_, GoRouterState state) => AssessmentDetailScreen(
      assessmentId: state.pathParameters['assessmentId']!,
    ),
  ),
  GuardedRoute(
    path: RoutePaths.answerKey,
    rule: const RouteAccessRule.requires(Permission.manageAnswerKey),
    builder: (_, GoRouterState state) => AnswerKeyScreen(
      assessmentId: state.pathParameters['assessmentId']!,
    ),
  ),
  GuardedRoute(
    path: RoutePaths.sessions,
    rule: const RouteAccessRule.requires(Permission.conductAssessment),
    insideShell: true,
    builder: (_, _) => const SessionsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.assessmentSession,
    rule: const RouteAccessRule.requires(Permission.conductAssessment),
    builder: (_, GoRouterState state) => AssessmentSessionScreen(
      sessionId: state.pathParameters['sessionId']!,
    ),
  ),
  GuardedRoute(
    path: RoutePaths.omrCapture,
    rule: const RouteAccessRule.requires(Permission.captureOmr),
    // A full-screen task, the same reasoning as a live session: a teacher
    // should not be able to wander off mid-capture by tapping the bar.
    builder: (_, GoRouterState state) => OmrCaptureScreen(
      sessionId: state.uri.queryParameters['sessionId'],
    ),
  ),
  GuardedRoute(
    path: RoutePaths.omrReview,
    rule: const RouteAccessRule.requires(Permission.reviewScanQuality),
    builder: (_, _) => const OmrReviewScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.omrValidationQueue,
    rule: const RouteAccessRule.requires(Permission.validateOmr),
    insideShell: true,
    builder: (_, _) => const OmrValidationQueueScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.omrValidationDetail,
    rule: const RouteAccessRule.requires(Permission.validateOmr),
    builder: (_, _) => const OmrValidationScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.results,
    rule: const RouteAccessRule.requires(Permission.viewResults),
    insideShell: true,
    builder: (_, _) => const ResultsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.studentResult,
    rule: const RouteAccessRule.requires(Permission.viewResults),
    insideShell: true,
    builder: (_, _) => const StudentResultScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.analytics,
    rule: const RouteAccessRule.requires(Permission.viewAnalytics),
    insideShell: true,
    builder: (_, _) => const AnalyticsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.reports,
    rule: const RouteAccessRule.requires(Permission.exportReports),
    insideShell: true,
    builder: (_, _) => const ReportsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.sync,
    rule: const RouteAccessRule.requires(Permission.syncSubmissions),
    insideShell: true,
    builder: (_, _) => const SyncScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.settings,
    // Any signed-in user can reach their own settings and sign out. Denying
    // that would leave a user with a stale role unable to do anything at all.
    rule: const RouteAccessRule.authenticated(),
    builder: (_, _) => const SettingsScreen(),
  ),
  GuardedRoute(
    path: RoutePaths.calibration,
    rule: const RouteAccessRule.requires(Permission.calibrateScanner),
    builder: (_, _) => const CalibrationScreen(),
  ),
];

/// Looks up the access rule for a resolved route path.
///
/// Matching is on the *declared pattern*, not the concrete location, so
/// `/schools/abc` resolves against `/schools/:schoolId`.
RouteAccessRule? ruleForMatchedPath(String matchedPath) {
  for (final GuardedRoute route in kAppRoutes) {
    if (route.path == matchedPath) {
      return route.rule;
    }
  }
  return null;
}

/// Builds the router.
///
/// Session state is watched through a [ChangeNotifier] adapter rather than by
/// rebuilding the router: recreating a `GoRouter` on every session change
/// discards navigation history and the current location.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _SessionRefreshNotifier refresh = _SessionRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'natco-shell',
  );

  final List<GuardedRoute> shellRoutes = kAppRoutes
      .where((GuardedRoute r) => r.insideShell)
      .toList(growable: false);
  final List<GuardedRoute> topLevelRoutes = kAppRoutes
      .where((GuardedRoute r) => !r.insideShell)
      .toList(growable: false);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) {
      final SessionState session = ref.read(sessionProvider);
      return RouteGuard.redirectFor(
        session: session,
        location: state.uri.toString(),
        // `fullPath`, not `matchedLocation`: the latter is the concrete
        // location with path parameters already substituted
        // (`/schools/<uuid>`), which never equals a declared template
        // (`/schools/:schoolId`) and made every parameterized route fail
        // closed for every role. `fullPath` is the template go_router
        // actually matched against.
        rule: ruleForMatchedPath(state.fullPath ?? state.matchedLocation),
        intendedLocation: state.uri.queryParameters[kIntendedLocationParam],
      );
    },
    routes: <RouteBase>[
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AppShell(child: child),
        routes: shellRoutes
            .map(
              (GuardedRoute route) =>
                  GoRoute(path: route.path, builder: route.builder),
            )
            .toList(growable: false),
      ),
      ...topLevelRoutes.map(
        (GuardedRoute route) =>
            GoRoute(path: route.path, builder: route.builder),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        const _RouteNotFoundScreen(),
  );
});

/// Bridges Riverpod's session state to go_router's `refreshListenable`.
final class _SessionRefreshNotifier extends ChangeNotifier {
  _SessionRefreshNotifier(Ref ref) {
    _subscription = ref.listen<SessionState>(
      sessionProvider,
      (SessionState? _, SessionState _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

/// A location that matches no route. Shown instead of a red error screen.
final class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.explore_off_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'That screen does not exist.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go(RoutePaths.dashboard),
                  child: const Text('Go to dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
