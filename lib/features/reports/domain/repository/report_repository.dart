/// Generates the nine CSV report types (requirement §32).
///
/// Every export is scoped exactly like every other list in the app — an
/// export can never widen what the caller could already see — and every
/// export is audited (`AuditAction.reportExported`), which is what makes
/// "every export audited" (docs/08-mvp-implementation-plan.md phase 11 exit
/// criteria) an invariant of the one method here rather than something each
/// call site has to remember.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/reports/domain/entity/generated_report.dart';
import 'package:natco_app/features/reports/domain/entity/report_type.dart';

abstract interface class ReportRepository {
  /// Generates [type] for [assessmentId] within [scope].
  ///
  /// [assessmentId] is ignored by [ReportType.syncFailures] (a device-local
  /// concern, not tied to one assessment) — passed uniformly anyway so the
  /// screen has one call shape for all nine types rather than a special case.
  Future<Result<GeneratedReport>> generateReport({
    required ReportType type,
    required String assessmentId,
    required AccessScope scope,
    required String actorUserId,
    required String actorRole,
  });
}
