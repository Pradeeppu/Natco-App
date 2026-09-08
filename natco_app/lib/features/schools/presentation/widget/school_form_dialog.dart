/// Create or edit a school.
///
/// Grades and mediums are entered as comma-separated text rather than a chip
/// picker: requirement section 10 forbids free-typing a *state, district,
/// cluster or school* — a school's own grade and medium offerings are the
/// school's own data entry, not a hierarchy lookup, so a plain text field is
/// the right amount of UI for this phase. A richer picker sourced from
/// `AppConfig.vocabularies` is a reasonable later refinement, not a
/// correctness gap.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

/// What the dialog collects. `null` fields on an edit mean "leave unchanged"
/// is not a thing here — the caller always sends a complete draft, matching
/// how `SchoolsRepository.updateSchool` takes a whole `School`.
final class SchoolDraft {
  const SchoolDraft({
    required this.schoolName,
    required this.schoolCode,
    required this.grades,
    required this.mediumsOfInstruction,
    this.address,
    this.pincode,
  });

  final String schoolName;
  final String schoolCode;
  final List<String> grades;
  final List<String> mediumsOfInstruction;
  final String? address;
  final String? pincode;
}

/// Shows the dialog. Pass [existing] to edit; omit to create. Returns the
/// draft on success, `null` if cancelled.
Future<SchoolDraft?> showSchoolFormDialog({
  required BuildContext context,
  School? existing,
  required Future<Failure?> Function(SchoolDraft draft) onSubmit,
}) => showDialog<SchoolDraft>(
  context: context,
  builder: (BuildContext context) =>
      _SchoolFormDialog(existing: existing, onSubmit: onSubmit),
);

final class _SchoolFormDialog extends StatefulWidget {
  const _SchoolFormDialog({required this.existing, required this.onSubmit});

  final School? existing;
  final Future<Failure?> Function(SchoolDraft draft) onSubmit;

  @override
  State<_SchoolFormDialog> createState() => _SchoolFormDialogState();
}

class _SchoolFormDialogState extends State<_SchoolFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _gradesController;
  late final TextEditingController _mediumsController;
  late final TextEditingController _addressController;
  late final TextEditingController _pincodeController;
  bool _isSubmitting = false;
  Failure? _failure;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final School? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.schoolName ?? '');
    _codeController = TextEditingController(text: existing?.schoolCode ?? '');
    _gradesController = TextEditingController(
      text: existing?.grades.join(', ') ?? '',
    );
    _mediumsController = TextEditingController(
      text: existing?.mediumsOfInstruction.join(', ') ?? '',
    );
    _addressController = TextEditingController(text: existing?.address ?? '');
    _pincodeController = TextEditingController(text: existing?.pincode ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _gradesController.dispose();
    _mediumsController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  static List<String> _splitList(String value) => value
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });
    final SchoolDraft draft = SchoolDraft(
      schoolName: _nameController.text.trim(),
      schoolCode: _codeController.text.trim(),
      grades: _splitList(_gradesController.text),
      mediumsOfInstruction: _splitList(_mediumsController.text),
      address: _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      pincode: _pincodeController.text.trim().isEmpty
          ? null
          : _pincodeController.text.trim(),
    );
    final Failure? failure = await widget.onSubmit(draft);
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _isSubmitting = false;
        _failure = failure;
      });
      return;
    }
    Navigator.of(context).pop(draft);
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_isEditing ? 'Edit school' : 'Add school'),
    content: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_failure != null) ...<Widget>[
              Text(
                _failure!.userMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameController,
              enabled: !_isSubmitting,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'School name'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeController,
              // The code identifies the school for life; changing it after
              // creation would break every OMR sheet already printed against
              // it, so it is fixed once set.
              enabled: !_isSubmitting && !_isEditing,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'School code',
                helperText: _isEditing ? 'Cannot be changed' : null,
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _gradesController,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Grades taught',
                helperText: 'Comma-separated, e.g. 1, 2, 3',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mediumsController,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Mediums of instruction',
                helperText: 'Comma-separated, e.g. English, Regional',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pincodeController,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Pincode (optional)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_isEditing ? 'Save' : 'Create'),
      ),
    ],
  );
}
