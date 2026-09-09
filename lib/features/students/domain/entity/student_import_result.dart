/// The outcome of a CSV student import.
///
/// Every row is attempted independently, so one rejected row never blocks
/// the rest and nothing is silently merged (requirement §11, §22).
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_draft.dart';

final class RejectedImportRow {
  const RejectedImportRow({required this.row, required this.reason});

  final StudentImportRow row;

  /// Why this row did not import — a duplicate, or a validation failure.
  /// [Failure.userMessage] is what the importer reads next to the row.
  final Failure reason;
}

final class StudentImportResult {
  const StudentImportResult({required this.imported, required this.rejected});

  final List<Student> imported;
  final List<RejectedImportRow> rejected;
}
