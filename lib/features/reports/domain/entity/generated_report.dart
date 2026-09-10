/// The output of one export: content ready to write to disk, plus what the
/// audit log and the UI need to say about it.
library;

import 'package:natco_app/features/reports/domain/entity/report_type.dart';

final class GeneratedReport {
  const GeneratedReport({
    required this.type,
    required this.fileName,
    required this.csvContent,
    required this.rowCount,
    required this.generatedAt,
  });

  final ReportType type;

  /// `{reportType}_{timestamp}.csv` — deliberately carries no student name
  /// or other personal identifier (Critical Rule 11): the identity stays in
  /// the file content, behind the same access check that gated generating
  /// it, not in something that lands bare in a downloads folder.
  final String fileName;

  final String csvContent;

  /// Excludes the header row — what a person means by "how many rows".
  final int rowCount;

  final DateTime generatedAt;
}
