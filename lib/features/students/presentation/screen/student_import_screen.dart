/// CSV bulk student import (`importStudents` permission — Super Admin
/// only).
///
/// Flow: choose the school → pick a `.csv` file → preview "N ready / M
/// rejected" with a named reason for every rejected row (parse errors and
/// duplicates alike) → commit, which imports every ready row independently
/// so one failure never blocks the rest (requirement §11, §22).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/presentation/widget/school_picker.dart';
import 'package:natco_app/features/students/data/service/csv_student_parser.dart';
import 'package:natco_app/features/students/domain/entity/student_draft.dart';
import 'package:natco_app/features/students/domain/entity/student_import_result.dart';

final class StudentImportScreen extends ConsumerStatefulWidget {
  const StudentImportScreen({super.key});

  @override
  ConsumerState<StudentImportScreen> createState() =>
      _StudentImportScreenState();
}

class _StudentImportScreenState extends ConsumerState<StudentImportScreen> {
  School? _school;
  String? _fileName;
  List<StudentImportRow>? _readyRows;
  List<CsvRowError> _parseErrors = const <CsvRowError>[];
  final Map<int, String> _duplicateReasons = <int, String>{};
  bool _loading = false;
  Failure? _loadFailure;
  bool _committing = false;
  StudentImportResult? _result;

  Future<void> _pickFile() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['csv'],
    );
    if (files.isEmpty) {
      return;
    }
    final PlatformFile file = files.first;
    setState(() {
      _fileName = file.name;
      _loading = true;
      _loadFailure = null;
      _result = null;
    });
    final Uint8List bytes = await file.readAsBytes();
    await _parseAndCheckDuplicates(bytes);
  }

  Future<void> _parseAndCheckDuplicates(List<int> bytes) async {
    final School? school = _school;
    if (school == null) {
      setState(() {
        _loading = false;
        _loadFailure = const ValidationFailure(
          userMessage: 'Choose a school before importing.',
        );
      });
      return;
    }
    final String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      setState(() {
        _loading = false;
        _loadFailure = const ValidationFailure(
          userMessage: 'That file is not readable as text (UTF-8).',
        );
      });
      return;
    }

    final CsvParseOutcome outcome = const CsvStudentParser().parse(content);
    final IdGenerator idGenerator = ref.read(idGeneratorProvider);
    final Map<String, List<int>> keyToRowNumbers = <String, List<int>>{};
    for (final StudentImportRow row in outcome.rows) {
      final String key = idGenerator.dedupeKey(<String>[
        school.schoolId,
        row.draft.studentName,
        row.draft.grade,
        row.draft.section,
        row.draft.dateOfBirth?.toUtc().toIso8601String() ?? '',
      ]);
      (keyToRowNumbers[key] ??= <int>[]).add(row.rowNumber);
    }

    final Map<int, String> duplicateReasons = <int, String>{};
    for (final MapEntry<String, List<int>> entry in keyToRowNumbers.entries) {
      if (entry.value.length > 1) {
        for (final int rowNumber in entry.value.skip(1)) {
          duplicateReasons[rowNumber] =
              'Same student as row ${entry.value.first} in this file.';
        }
      }
    }

    final Result<Set<String>> existing = await ref
        .read(studentRepositoryProvider)
        .existingDedupeKeys(keyToRowNumbers.keys.toSet());
    if (!mounted) {
      return;
    }
    if (existing.isFailure) {
      setState(() {
        _loading = false;
        _loadFailure = existing.failureOrNull;
      });
      return;
    }
    for (final String key in existing.valueOrNull!) {
      final int firstRow = keyToRowNumbers[key]!.first;
      duplicateReasons.putIfAbsent(
        firstRow,
        () => 'This student has already been registered.',
      );
    }

    setState(() {
      _loading = false;
      _parseErrors = outcome.errors;
      _duplicateReasons
        ..clear()
        ..addAll(duplicateReasons);
      _readyRows = outcome.rows
          .where((StudentImportRow r) => !duplicateReasons.containsKey(r.rowNumber))
          .toList(growable: false);
    });
  }

  Future<void> _commit() async {
    final School? school = _school;
    final List<StudentImportRow>? ready = _readyRows;
    if (school == null || ready == null || ready.isEmpty) {
      return;
    }
    setState(() => _committing = true);
    final SessionState session = ref.read(sessionProvider);
    final Result<StudentImportResult> result = await ref
        .read(studentRepositoryProvider)
        .importStudents(
          rows: ready,
          schoolId: school.schoolId,
          actorUserId: session.session?.user.userId ?? 'unknown',
          actorRole: session.session?.user.role.wireName ?? 'UNKNOWN',
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _committing = false;
      if (result.isSuccess) {
        _result = result.valueOrNull;
      } else {
        _loadFailure = result.failureOrNull;
      }
    });
  }

  int get _rejectedCount => _parseErrors.length + _duplicateReasons.length;

  @override
  Widget build(BuildContext context) {
    final StudentImportResult? result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Import students')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: result != null ? _resultBody(result) : _setupBody(),
        ),
      ),
    );
  }

  Widget _setupBody() {
    final List<StudentImportRow>? ready = _readyRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SchoolPicker(
          onSelected: (School school) => setState(() {
            _school = school;
            _fileName = null;
            _readyRows = null;
            _parseErrors = const <CsvRowError>[];
            _duplicateReasons.clear();
          }),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _school == null || _loading ? null : _pickFile,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(_fileName ?? 'Choose CSV file'),
        ),
        const SizedBox(height: 8),
        Text(
          'Expected columns: ${kRequiredCsvColumns.join(', ')} '
          '(required), ${kOptionalCsvColumns.join(', ')} (optional).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        if (_loading) const LoadingView(message: 'Checking for duplicates…'),
        if (_loadFailure != null)
          FailureView(
            failure: _loadFailure!,
            onRetry: _fileName == null ? null : _pickFile,
          ),
        if (ready != null) ...<Widget>[
          InfoBanner(
            isWarning: _rejectedCount > 0,
            icon: _rejectedCount > 0
                ? Icons.warning_amber_outlined
                : Icons.check_circle_outline,
            message: '${ready.length} ready to import'
                '${_rejectedCount > 0 ? ', $_rejectedCount rejected' : ''}.',
          ),
          const SizedBox(height: 16),
          ..._parseErrors.map(
            (CsvRowError e) => _RejectedRowTile(
              rowNumber: e.rowNumber,
              reason: e.reason,
            ),
          ),
          ..._duplicateReasons.entries.map(
            (MapEntry<int, String> e) => _RejectedRowTile(
              rowNumber: e.key,
              reason: e.value,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: ready.isEmpty || _committing ? null : _commit,
            child: _committing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text('Import ${ready.length} student(s)'),
          ),
        ],
      ],
    );
  }

  Widget _resultBody(StudentImportResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InfoBanner(
          isWarning: result.rejected.isNotEmpty,
          icon: Icons.check_circle_outline,
          message: '${result.imported.length} imported'
              '${result.rejected.isNotEmpty ? ', ${result.rejected.length} rejected' : ''}.',
        ),
        const SizedBox(height: 16),
        ...result.rejected.map(
          (RejectedImportRow r) => _RejectedRowTile(
            rowNumber: r.row.rowNumber,
            reason: r.reason.userMessage,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

final class _RejectedRowTile extends StatelessWidget {
  const _RejectedRowTile({required this.rowNumber, required this.reason});

  final int rowNumber;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Row $rowNumber: $reason',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
