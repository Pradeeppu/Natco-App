/// Providers for the reports screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/reports/domain/entity/generated_report.dart';
import 'package:natco_app/features/reports/domain/entity/report_type.dart';

/// One-shot report generation, triggered by a button tap rather than watched
/// automatically — an export is a deliberate, audited act
/// (`AuditAction.reportExported`), not something that should silently re-run
/// on every rebuild.
final class ReportGenerationController extends Notifier<AsyncValue<GeneratedReport?>> {
  @override
  AsyncValue<GeneratedReport?> build() => const AsyncValue.data(null);

  Future<void> generate({
    required ReportType type,
    required String assessmentId,
    required String actorUserId,
    required String actorRole,
  }) async {
    state = const AsyncValue.loading();
    final AccessScope scope =
        ref.read(sessionProvider).authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
    final Result<GeneratedReport> result = await ref
        .read(reportRepositoryProvider)
        .generateReport(
          type: type,
          assessmentId: assessmentId,
          scope: scope,
          actorUserId: actorUserId,
          actorRole: actorRole,
        );
    state = switch (result) {
      Success<GeneratedReport>(:final value) => AsyncValue.data(value),
      FailureResult<GeneratedReport>(:final failure) => AsyncValue.error(
        failure,
        StackTrace.current,
      ),
    };
  }

  void clear() => state = const AsyncValue.data(null);
}

final NotifierProvider<ReportGenerationController, AsyncValue<GeneratedReport?>>
reportGenerationControllerProvider =
    NotifierProvider<ReportGenerationController, AsyncValue<GeneratedReport?>>(
      ReportGenerationController.new,
    );
