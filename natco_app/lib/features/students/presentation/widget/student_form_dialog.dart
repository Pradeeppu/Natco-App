/// Create or edit a single student.
///
/// [allowedGrades] comes from the school's own `grades` list, so a student
/// cannot be assigned to a grade the school does not teach — the same
/// controlled-vocabulary posture requirement section 10 requires for the
/// geographic hierarchy, applied here to grade.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/students/domain/entity/gender.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

final class StudentDraft {
  const StudentDraft({
    required this.studentName,
    required this.gender,
    required this.grade,
    required this.section,
    required this.mediumOfInstruction,
    required this.language,
    this.dateOfBirth,
    this.electiveSubject,
  });

  final String studentName;
  final Gender gender;
  final String grade;
  final String section;
  final String mediumOfInstruction;
  final String language;
  final DateTime? dateOfBirth;
  final String? electiveSubject;
}

const List<String> _sections = <String>['A', 'B', 'C', 'D', 'E'];

Future<StudentDraft?> showStudentFormDialog({
  required BuildContext context,
  required List<String> allowedGrades,
  required List<String> allowedMediums,
  Student? existing,
  required Future<Failure?> Function(StudentDraft draft) onSubmit,
}) => showDialog<StudentDraft>(
  context: context,
  builder: (BuildContext context) => _StudentFormDialog(
    allowedGrades: allowedGrades,
    allowedMediums: allowedMediums,
    existing: existing,
    onSubmit: onSubmit,
  ),
);

final class _StudentFormDialog extends StatefulWidget {
  const _StudentFormDialog({
    required this.allowedGrades,
    required this.allowedMediums,
    required this.existing,
    required this.onSubmit,
  });

  final List<String> allowedGrades;
  final List<String> allowedMediums;
  final Student? existing;
  final Future<Failure?> Function(StudentDraft draft) onSubmit;

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _languageController;
  late final TextEditingController _electiveController;
  Gender _gender = Gender.notSpecified;
  String? _grade;
  String _section = _sections.first;
  String? _medium;
  DateTime? _dateOfBirth;
  bool _isSubmitting = false;
  Failure? _failure;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Student? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.studentName ?? '');
    _languageController = TextEditingController(
      text: existing?.language ?? '',
    );
    _electiveController = TextEditingController(
      text: existing?.electiveSubject ?? '',
    );
    _gender = existing?.gender ?? Gender.notSpecified;
    _grade = existing?.grade ?? widget.allowedGrades.firstOrNull;
    _section = existing?.section ?? _sections.first;
    _medium = existing?.mediumOfInstruction ?? widget.allowedMediums.firstOrNull;
    _dateOfBirth = existing?.dateOfBirth;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _languageController.dispose();
    _electiveController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 10),
      firstDate: DateTime(now.year - 25),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_grade == null || _medium == null) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });
    final StudentDraft draft = StudentDraft(
      studentName: _nameController.text.trim(),
      gender: _gender,
      grade: _grade!,
      section: _section,
      mediumOfInstruction: _medium!,
      language: _languageController.text.trim(),
      dateOfBirth: _dateOfBirth,
      electiveSubject: _electiveController.text.trim().isEmpty
          ? null
          : _electiveController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isEditing ? 'Edit student' : 'Add student'),
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
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                enabled: !_isSubmitting,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Student name'),
                validator: (String? v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _grade,
                      decoration: const InputDecoration(labelText: 'Grade'),
                      items: widget.allowedGrades
                          .map(
                            (String g) => DropdownMenuItem<String>(
                              value: g,
                              child: Text(g),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isSubmitting
                          ? null
                          : (String? value) => setState(() => _grade = value),
                      validator: (String? v) => v == null ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _section,
                      decoration: const InputDecoration(labelText: 'Section'),
                      items: _sections
                          .map(
                            (String s) => DropdownMenuItem<String>(
                              value: s,
                              child: Text(s),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isSubmitting
                          ? null
                          : (String? value) =>
                                setState(() => _section = value ?? _section),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _medium,
                decoration: const InputDecoration(
                  labelText: 'Medium of instruction',
                ),
                items: widget.allowedMediums
                    .map(
                      (String m) =>
                          DropdownMenuItem<String>(value: m, child: Text(m)),
                    )
                    .toList(growable: false),
                onChanged: _isSubmitting
                    ? null
                    : (String? value) => setState(() => _medium = value),
                validator: (String? v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Gender>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: Gender.values
                    .map(
                      (Gender g) => DropdownMenuItem<Gender>(
                        value: g,
                        child: Text(g.wireName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isSubmitting
                    ? null
                    : (Gender? value) =>
                          setState(() => _gender = value ?? _gender),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _isSubmitting ? null : _pickDateOfBirth,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date of birth (optional)',
                  ),
                  child: Text(
                    _dateOfBirth == null
                        ? 'Not set'
                        : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _languageController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(labelText: 'Language'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _electiveController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Elective subject (optional)',
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
              : Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
