/// CSV import: paste, preview, import.
///
/// Text is pasted rather than picked from a file: no file-picker dependency
/// is in this project's dependency list yet
/// (docs/09-dependencies.md), and a multi-line paste field needs none while
/// exercising exactly the same [StudentCsvImporter] a real file-based import
/// would. Swapping the source to an actual file later changes only how this
/// dialog gets its `csvText` — the parsing and persistence paths are already
/// the real ones.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/features/students/domain/entity/student_import_report.dart';

/// Shows the paste-and-import dialog. [onImport] performs the actual import
/// and returns the report; this widget only drives the two-step UI
/// (paste → review) and renders whatever report comes back.
Future<void> showCsvImportDialog({
  required BuildContext context,
  required Future<StudentImportReport?> Function(String csvText) onImport,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => _CsvImportDialog(onImport: onImport),
);

final class _CsvImportDialog extends StatefulWidget {
  const _CsvImportDialog({required this.onImport});

  final Future<StudentImportReport?> Function(String csvText) onImport;

  @override
  State<_CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<_CsvImportDialog> {
  final TextEditingController _csvController = TextEditingController();
  bool _isImporting = false;
  StudentImportReport? _report;

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_csvController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isImporting = true);
    final StudentImportReport? report = await widget.onImport(
      _csvController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isImporting = false;
      _report = report;
    });
  }

  @override
  Widget build(BuildContext context) {
    final StudentImportReport? report = _report;
    return AlertDialog(
      title: const Text('Import students'),
      content: SizedBox(
        width: 480,
        child: report == null ? _buildPasteStep() : _buildReportStep(report),
      ),
      actions: report == null
          ? <Widget>[
              TextButton(
                onPressed: _isImporting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _isImporting ? null : _import,
                child: _isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Import'),
              ),
            ]
          : <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
    );
  }

  Widget _buildPasteStep() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const Text(
        'Paste CSV with columns: studentName, grade, section, and '
        'optionally gender, dateOfBirth, mediumOfInstruction, language, '
        'electiveSubject, externalStudentCode.',
        style: TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _csvController,
        enabled: !_isImporting,
        maxLines: 10,
        minLines: 6,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'studentName,grade,section\nRavi Kumar,5,A\n...',
          alignLabelWithHint: true,
        ),
      ),
    ],
  );

  Widget _buildReportStep(StudentImportReport report) {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                report.hasFailures
                    ? Icons.warning_amber_outlined
                    : Icons.check_circle_outline,
                color: report.hasFailures
                    ? theme.colorScheme.error
                    : Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${report.createdCount} of ${report.totalRows} '
                  'student${report.totalRows == 1 ? '' : 's'} imported',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (report.hasFailures) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              '${report.failedCount} row${report.failedCount == 1 ? '' : 's'} '
              'could not be imported:',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final StudentImportParseError error in report.parseErrors)
              _FailureRow(
                rowNumber: error.rowNumber,
                label: error.reason,
                icon: Icons.report_problem_outlined,
              ),
            for (final StudentImportRejection rejection in report.rejections)
              _FailureRow(
                rowNumber: rejection.rowNumber,
                label: '${rejection.studentName}: ${rejection.detail}',
                icon: rejection.reason == ImportRejectionReason.duplicate
                    ? Icons.content_copy_outlined
                    : Icons.report_problem_outlined,
              ),
          ],
        ],
      ),
    );
  }
}

final class _FailureRow extends StatelessWidget {
  const _FailureRow({
    required this.rowNumber,
    required this.label,
    required this.icon,
  });

  final int rowNumber;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Row $rowNumber: $label',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
