/// The role-specific home dashboard.
///
/// One deliberate restraint: this screen shows **no assessment metrics yet**.
/// Requirement section 27 wants OMRs captured, pending, needing validation and
/// average scores, and every one of those numbers comes from data that phases
/// 5 to 10 produce. Rendering plausible-looking placeholders in their place
/// would be inventing data, which is the one thing this product must never do
/// (Critical Rules 3 and 14). Instead the dashboard shows what is real today —
/// who you are, what you may do, the state of your session and connection —
/// and says plainly where the metrics will come from.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/services/connectivity_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/dashboard/presentation/widget/quick_action_grid.dart';

final class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final AuthSessionSnapshot? snapshot = AuthSessionSnapshot.of(session);
    if (snapshot == null) {
      // The router guarantees a session here; this is belt-and-braces so a
      // race during sign-out renders a spinner rather than throwing.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Clock clock = ref.watch(clockProvider);
    final AsyncValue<ConnectionStatus> connection = ref.watch(
      connectionStatusProvider,
    );
    final Authorization authorization = session.authorization;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.go(RoutePaths.settings),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: <Widget>[
            if (snapshot.isOffline) ...<Widget>[
              const _OfflineSessionNotice(),
              const SizedBox(height: 16),
            ],
            _Greeting(user: snapshot.user, clock: clock),
            const SizedBox(height: 20),
            _IdentityCard(user: snapshot.user, connection: connection.value),
            const SizedBox(height: 28),
            Text('Next action', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            QuickActionGrid(
              actions: _actionsForRole(snapshot.user.role),
              authorization: authorization,
              onSelected: (QuickAction action) => context.go(action.route),
            ),
            const SizedBox(height: 20),
            const _MetricsPendingCard(),
          ],
        ),
      ),
    );
  }

  /// Actions ordered by what the role does most, with the role's principal
  /// task marked primary.
  static List<QuickAction> _actionsForRole(UserRole role) => switch (role) {
    UserRole.pstTeacher => const <QuickAction>[
      QuickAction(
        label: 'Start or continue assessment',
        description: 'Run a session for your assigned grade and section',
        icon: Icons.play_circle_outline,
        route: RoutePaths.assessments,
        permission: Permission.conductAssessment,
        isPrimary: true,
      ),
      QuickAction(
        label: 'Capture OMR',
        description: 'Photograph a sheet, or pick one from the gallery',
        icon: Icons.photo_camera_outlined,
        route: RoutePaths.omrCapture,
        permission: Permission.captureOmr,
      ),
      QuickAction(
        label: 'Sync status',
        description: 'Pending uploads, failures and retries',
        icon: Icons.sync_outlined,
        route: RoutePaths.sync,
        permission: Permission.syncSubmissions,
      ),
      QuickAction(
        label: 'My students',
        description: 'Students assigned to you',
        icon: Icons.groups_outlined,
        route: RoutePaths.students,
        permission: Permission.viewStudents,
      ),
    ],
    UserRole.scannerOperator => const <QuickAction>[
      QuickAction(
        label: 'Capture OMR',
        description: 'Scan sheets and check quality',
        icon: Icons.photo_camera_outlined,
        route: RoutePaths.omrCapture,
        permission: Permission.captureOmr,
        isPrimary: true,
      ),
      QuickAction(
        label: 'Sync status',
        description: 'Pending uploads, failures and retries',
        icon: Icons.sync_outlined,
        route: RoutePaths.sync,
        permission: Permission.syncSubmissions,
      ),
    ],
    UserRole.supervisor => const <QuickAction>[
      QuickAction(
        label: 'Validation queue',
        description: 'Review answers the scanner was unsure about',
        icon: Icons.rule_folder_outlined,
        route: RoutePaths.omrValidationQueue,
        permission: Permission.validateOmr,
        isPrimary: true,
      ),
      QuickAction(
        label: 'Monitor schools',
        description: 'Progress across your assigned area',
        icon: Icons.school_outlined,
        route: RoutePaths.schools,
        permission: Permission.viewSchools,
      ),
      QuickAction(
        label: 'Sync failures',
        description: 'Devices with uploads that did not complete',
        icon: Icons.sync_problem_outlined,
        route: RoutePaths.sync,
        permission: Permission.syncSubmissions,
      ),
      QuickAction(
        label: 'Analytics',
        description: 'School and cluster performance',
        icon: Icons.insights_outlined,
        route: RoutePaths.analytics,
        permission: Permission.viewAnalytics,
      ),
    ],
    UserRole.assessmentAdmin => const <QuickAction>[
      QuickAction(
        label: 'Assessments',
        description: 'Create assessments, questions and answer keys',
        icon: Icons.assignment_outlined,
        route: RoutePaths.assessments,
        permission: Permission.manageAssessments,
        isPrimary: true,
      ),
      QuickAction(
        label: 'Analytics',
        description: 'Question-level and assessment performance',
        icon: Icons.insights_outlined,
        route: RoutePaths.analytics,
        permission: Permission.viewAnalytics,
      ),
      QuickAction(
        label: 'Reports',
        description: 'Export assessment and question analysis',
        icon: Icons.download_outlined,
        route: RoutePaths.reports,
        permission: Permission.exportReports,
      ),
    ],
    UserRole.superAdmin => const <QuickAction>[
      QuickAction(
        label: 'Schools and hierarchy',
        description: 'States, districts, clusters and schools',
        icon: Icons.account_tree_outlined,
        route: RoutePaths.schools,
        permission: Permission.manageSchools,
        isPrimary: true,
      ),
      QuickAction(
        label: 'Students',
        description: 'Master data and imports',
        icon: Icons.groups_outlined,
        route: RoutePaths.students,
        permission: Permission.manageStudents,
      ),
      QuickAction(
        label: 'Assessments',
        description: 'Assessments, questions and answer keys',
        icon: Icons.assignment_outlined,
        route: RoutePaths.assessments,
        permission: Permission.manageAssessments,
      ),
      QuickAction(
        label: 'Scanner calibration',
        description: 'Measure accuracy and adjust thresholds',
        icon: Icons.tune_outlined,
        route: RoutePaths.calibration,
        permission: Permission.calibrateScanner,
      ),
    ],
    UserRole.viewer => const <QuickAction>[
      QuickAction(
        label: 'Analytics',
        description: 'Dashboards for your area',
        icon: Icons.insights_outlined,
        route: RoutePaths.analytics,
        permission: Permission.viewAnalytics,
        isPrimary: true,
      ),
      QuickAction(
        label: 'Reports',
        description: 'Export permitted summaries',
        icon: Icons.download_outlined,
        route: RoutePaths.reports,
        permission: Permission.exportReports,
      ),
    ],
  };
}

/// A non-null view of an authenticated session, so the dashboard does not
/// repeat null checks.
final class AuthSessionSnapshot {
  const AuthSessionSnapshot({required this.user, required this.isOffline});

  static AuthSessionSnapshot? of(SessionState state) => switch (state) {
    SessionAuthenticated(:final bool isOffline, :final session) =>
      AuthSessionSnapshot(user: session.user, isOffline: isOffline),
    _ => null,
  };

  final AppUser user;
  final bool isOffline;
}

final class _Greeting extends StatelessWidget {
  const _Greeting({required this.user, required this.clock});

  final AppUser user;
  final Clock clock;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _greetingFor(clock.nowUtc().toLocal().hour),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(user.shortName, style: theme.textTheme.headlineSmall),
      ],
    );
  }

  static String _greetingFor(int hour) {
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 17) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }
}

/// Role, scope and connection — the facts the app can state today.
final class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user, required this.connection});

  final AppUser user;
  final ConnectionStatus? connection;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                StatusChip(
                  label: user.role.displayName,
                  tone: StatusTone.neutral,
                  icon: Icons.badge_outlined,
                ),
                _connectionChip(),
              ],
            ),
            const SizedBox(height: 16),
            _Row(label: 'Access level', value: _scopeLevelLabel(user.scope)),
            _Row(label: 'Assigned area', value: _scopeSummary(user.scope)),
            if (user.scope.gradeSections.isNotEmpty)
              _Row(
                label: 'Grade / section',
                value: (user.scope.gradeSections.toList()..sort())
                    .map((GradeSection gs) => gs.displayName)
                    .join(', '),
              ),
            _Row(
              label: 'Permissions',
              value: '${user.permissions.length} granted',
            ),
            const SizedBox(height: 12),
            Text(
              'Your assigned area limits every screen, list and report to the '
              'schools you are responsible for.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionChip() => switch (connection) {
    null => const StatusChip(
      label: 'Checking connection',
      tone: StatusTone.pending,
    ),
    ConnectionStatus.offline => const StatusChip(
      label: 'Offline',
      tone: StatusTone.warning,
      icon: Icons.cloud_off_outlined,
    ),
    ConnectionStatus.interfaceOnly => const StatusChip(
      label: 'No internet',
      tone: StatusTone.warning,
      icon: Icons.wifi_tethering_error,
    ),
    ConnectionStatus.onlineMetered => const StatusChip(
      label: 'Mobile data',
      tone: StatusTone.neutral,
      icon: Icons.signal_cellular_alt,
    ),
    ConnectionStatus.onlineUnmetered => const StatusChip(
      label: 'Online',
      tone: StatusTone.success,
      icon: Icons.cloud_done_outlined,
    ),
  };

  static String _scopeLevelLabel(AccessScope scope) => switch (scope.level) {
    ScopeLevel.global => 'All states',
    ScopeLevel.state => 'State',
    ScopeLevel.district => 'District',
    ScopeLevel.cluster => 'Cluster',
    ScopeLevel.school => 'School',
  };

  static String _scopeSummary(AccessScope scope) {
    if (scope.isGlobal) {
      return 'Every school in the programme';
    }
    final int count = scope.definingIds.length;
    final String noun = switch (scope.level) {
      ScopeLevel.global => 'area',
      ScopeLevel.state => count == 1 ? 'state' : 'states',
      ScopeLevel.district => count == 1 ? 'district' : 'districts',
      ScopeLevel.cluster => count == 1 ? 'cluster' : 'clusters',
      ScopeLevel.school => count == 1 ? 'school' : 'schools',
    };
    return '$count $noun';
  }
}

final class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _OfflineSessionNotice extends StatelessWidget {
  const _OfflineSessionNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.statusColors.warningContainer,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.cloud_off_outlined,
            size: 20,
            color: theme.statusColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Working from your saved session. Your role and assignments '
              'will be refreshed the next time you are online.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.statusColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says where the metrics come from, instead of showing invented ones.
final class _MetricsPendingCard extends StatelessWidget {
  const _MetricsPendingCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.query_stats_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Assessment metrics', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Counts for OMRs captured, processed, pending and awaiting '
              'validation, plus average scores, appear here once the capture, '
              'scoring and analytics phases are in place. They are left blank '
              'deliberately: this app never shows a number it has not '
              'measured.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
