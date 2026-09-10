/// Report generation and export.
///
/// Reads `assessmentId` from the query string, the same convention as
/// Results and Analytics — `sync_failures` is the one report type that
/// ignores it (a device-local concern, not tied to one sitting).
///
/// Every export here is real: a genuine CSV built from scoped, real records,
/// audited the moment it is generated. What is *not* here yet is a share
/// sheet or a written file on disk — that needs `path_provider`'s platform
/// channel, which (like camera access) cannot be verified without a device
/// in this environment, so this screen shows the generated content rather
/// than claim a save succeeded that was never actually exercised.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/reports/domain/entity/generated_report.dart';
import 'package:natco_app/features/reports/domain/entity/report_type.dart';
import 'package:natco_app/features/reports/presentation/controller/report_controllers.dart';

final class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? assessmentId = GoRouterState.of(
      context,
    ).uri.queryParameters['assessmentId'];
    final AsyncValue<GeneratedReport?> generated = ref.watch(
      reportGenerationControllerProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            if (assessmentId == null)
              const InfoBanner(
                message:
                    'No assessment selected. Every report except "Sync '
                    'failures" needs one — open this screen from an '
                    "assessment's detail page for those.",
                icon: Icons.info_outline,
              )
            else
              const InfoBanner(
                message:
                    'Scoped to what your account can already see — an '
                    'export can never widen your reach.',
              ),
            const SizedBox(height: 16),
            ...ReportType.values.map(
              (ReportType type) => _ReportTile(
                type: type,
                assessmentId: assessmentId,
                enabled: assessmentId != null || type == ReportType.syncFailures,
              ),
            ),
            if (generated is AsyncError)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: InfoBanner(
                  message: (generated.error is Failure
                          ? (generated.error! as Failure).userMessage
                          : 'That report could not be generated.'),
                  icon: Icons.error_outline,
                  isWarning: true,
                ),
              ),
            if (generated case AsyncData<GeneratedReport?>(value: final GeneratedReport report))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _GeneratedReportCard(report: report),
              ),
          ],
        ),
      ),
    );
  }
}

final class _ReportTile extends ConsumerWidget {
  const _ReportTile({
    required this.type,
    required this.assessmentId,
    required this.enabled,
  });

  final ReportType type;
  final String? assessmentId;
  final bool enabled;

  static const Map<ReportType, IconData> _icons = <ReportType, IconData>{
    ReportType.studentResult: Icons.person_outline,
    ReportType.schoolSummary: Icons.school_outlined,
    ReportType.clusterSummary: Icons.hub_outlined,
    ReportType.districtSummary: Icons.location_city_outlined,
    ReportType.assessmentSummary: Icons.assignment_outlined,
    ReportType.questionAnalysis: Icons.query_stats_outlined,
    ReportType.omrProcessing: Icons.document_scanner_outlined,
    ReportType.validation: Icons.how_to_reg_outlined,
    ReportType.syncFailures: Icons.cloud_off_outlined,
  };

  Future<void> _export(WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    final String? actorUserId = session.authorization.user?.userId;
    final String? actorRole = session.authorization.user?.role.wireName;
    if (actorUserId == null || actorRole == null) {
      return;
    }
    await ref
        .read(reportGenerationControllerProvider.notifier)
        .generate(
          type: type,
          assessmentId: assessmentId ?? '',
          actorUserId: actorUserId,
          actorRole: actorRole,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GeneratedReport?> generated = ref.watch(
      reportGenerationControllerProvider,
    );
    final bool isGeneratingThis =
        generated.isLoading; // only one generation runs at a time
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_icons[type], color: enabled ? null : Theme.of(context).disabledColor),
        title: Text(type.displayName),
        subtitle: Text(type.description),
        trailing: isGeneratingThis
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                onPressed: enabled ? () => _export(ref) : null,
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Export ${type.displayName} as CSV',
              ),
      ),
    );
  }
}

final class _GeneratedReportCard extends ConsumerWidget {
  const _GeneratedReportCard({required this.report});

  final GeneratedReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final List<String> lines = report.csvContent.split(RegExp(r'\r?\n'));
    final List<String> preview = lines.take(6).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_outline, color: status.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(report.fileName, style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  onPressed: () => ref
                      .read(reportGenerationControllerProvider.notifier)
                      .clear(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${report.rowCount} row(s) · recorded in the audit log',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  preview.join('\n') +
                      (lines.length > preview.length ? '\n…' : ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
