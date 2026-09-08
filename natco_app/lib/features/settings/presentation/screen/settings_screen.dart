/// Settings: who you are, what this build is, and how to get out.
///
/// Also the home of the diagnostics view, which matters more than it looks:
/// requirement section 40 asks that diagnostic detail be logged rather than
/// shown, and a field user with no cable needs some way to hand that detail to
/// support. The log buffer is already redacted, so what is displayed here
/// contains no password, token or student personal data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/app_config.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

final class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final AppConfig config = ref.watch(appConfigProvider);
    final DeviceInfoService device = ref.watch(deviceInfoProvider);
    final user = session.session?.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            if (user != null) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(user.displayName),
                subtitle: Text('${user.email}\n${user.role.displayName}'),
                isThreeLine: true,
              ),
              const Divider(),
            ],
            const _SectionHeader(label: 'Build'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App version'),
              subtitle: Text('${device.appVersion} (${device.buildNumber})'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_ethernet),
              title: const Text('Environment'),
              subtitle: Text(config.environment.name),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('OMR template'),
              subtitle: Text(
                '${config.omrTemplateVersion} · thresholds v'
                '${config.scannerThresholds.version}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: const Text('Device'),
              subtitle: Text(
                '${device.platformDescription}\n${device.deviceId}',
              ),
              isThreeLine: true,
            ),
            const Divider(),
            const _SectionHeader(label: 'Your access'),
            if (user != null)
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Permissions'),
                subtitle: Text('${user.permissions.length} granted'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => _PermissionListScreen(
                      permissions: user.permissions.toList(growable: false)
                        ..sort(
                          (Permission a, Permission b) =>
                              a.wireName.compareTo(b.wireName),
                        ),
                    ),
                  ),
                ),
              ),
            if (session.authorization.can(Permission.calibrateScanner))
              ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Scanner calibration'),
                subtitle: const Text('Measure accuracy and set thresholds'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context).pushNamed(RoutePaths.calibration),
              ),
            if (config.featureFlags.showDiagnosticsScreen) ...<Widget>[
              const Divider(),
              const _SectionHeader(label: 'Support'),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Diagnostics'),
                subtitle: const Text(
                  'Recent activity, with sensitive data '
                  'already removed',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const _DiagnosticsScreen(),
                  ),
                ),
              ),
            ],
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Signing out is confirmed because it ends offline access: a user in a
  /// school with no connection cannot sign back in until they have one.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need an internet connection to sign in again. Anything '
          'already captured on this device stays saved and will upload after '
          'you sign back in.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(sessionProvider.notifier).signOut();
    }
  }
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

final class _PermissionListScreen extends StatelessWidget {
  const _PermissionListScreen({required this.permissions});

  final List<Permission> permissions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Permissions')),
    body: SafeArea(
      child: ListView.separated(
        itemCount: permissions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final Permission permission = permissions[index];
          return ListTile(
            leading: const Icon(Icons.check, size: 20),
            title: Text(permission.wireName),
            subtitle: Text('You may ${permission.actionPhrase}.'),
          );
        },
      ),
    ),
  );
}

final class _DiagnosticsScreen extends ConsumerWidget {
  const _DiagnosticsScreen();

  /// Fields are already redacted by [LogRedactor] before they reach the
  /// buffer, so rendering them here cannot leak a token or a student name.
  static String _fieldsSuffix(LogRecord record) {
    final String header =
        '${record.level.label} \u00b7 ${record.timestamp.toIso8601String()}';
    return record.fields.isEmpty ? header : '$header\n${record.fields}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<LogRecord> records = ref
        .watch(logBufferProvider)
        .records
        .reversed
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: SafeArea(
        child: records.isEmpty
            ? const Center(child: Text('Nothing recorded yet.'))
            : ListView.separated(
                itemCount: records.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final LogRecord record = records[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      record.event,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _fieldsSuffix(record),
                      style: theme.textTheme.bodySmall,
                    ),
                    isThreeLine: record.fields.isNotEmpty,
                  );
                },
              ),
      ),
    );
  }
}
