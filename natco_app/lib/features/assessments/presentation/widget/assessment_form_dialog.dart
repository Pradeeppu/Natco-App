/// Create an assessment.
///
/// Options are entered as comma-separated text, the same convention
/// `SchoolFormDialog` uses for grades and mediums — a real option-set picker
/// sourced from `AppConfig.vocabularies` is a reasonable later refinement,
/// not a correctness gap.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';

final class AssessmentDraft {
  const AssessmentDraft({
    required this.assessmentName,
    required this.assessmentCode,
    required this.academicYear,
    required this.grade,
    required this.subject,
    required this.questionCount,
    required this.options,
    required this.durationMinutes,
    this.instructions = '',
  });

  final String assessmentName;
  final String assessmentCode;
  final String academicYear;
  final String grade;
  final String subject;
  final int questionCount;
  final List<String> options;
  final int durationMinutes;
  final String instructions;
}

Future<AssessmentDraft?> showAssessmentFormDialog({
  required BuildContext context,
  required Future<Failure?> Function(AssessmentDraft draft) onSubmit,
}) => showDialog<AssessmentDraft>(
  context: context,
  builder: (BuildContext context) => _AssessmentFormDialog(onSubmit: onSubmit),
);

final class _AssessmentFormDialog extends StatefulWidget {
  const _AssessmentFormDialog({required this.onSubmit});

  final Future<Failure?> Function(AssessmentDraft draft) onSubmit;

  @override
  State<_AssessmentFormDialog> createState() => _AssessmentFormDialogState();
}

class _AssessmentFormDialogState extends State<_AssessmentFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _academicYearController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _questionCountController = TextEditingController(
    text: '10',
  );
  final TextEditingController _optionsController = TextEditingController(
    text: 'A, B, C, D',
  );
  final TextEditingController _durationController = TextEditingController(
    text: '45',
  );
  final TextEditingController _instructionsController = TextEditingController();
  bool _isSubmitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _academicYearController.dispose();
    _gradeController.dispose();
    _subjectController.dispose();
    _questionCountController.dispose();
    _optionsController.dispose();
    _durationController.dispose();
    _instructionsController.dispose();
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
    final AssessmentDraft draft = AssessmentDraft(
      assessmentName: _nameController.text.trim(),
      assessmentCode: _codeController.text.trim(),
      academicYear: _academicYearController.text.trim(),
      grade: _gradeController.text.trim(),
      subject: _subjectController.text.trim(),
      questionCount: int.tryParse(_questionCountController.text.trim()) ?? 0,
      options: _splitList(_optionsController.text),
      durationMinutes: int.tryParse(_durationController.text.trim()) ?? 0,
      instructions: _instructionsController.text.trim(),
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

  String? _positiveInt(String? value) {
    final int? parsed = int.tryParse(value?.trim() ?? '');
    return (parsed == null || parsed <= 0) ? 'Must be a positive number' : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add assessment'),
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
              decoration: const InputDecoration(labelText: 'Assessment name'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeController,
              enabled: !_isSubmitting,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Assessment code',
                helperText: 'Printed on the OMR sheet; fixed once created',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _academicYearController,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Academic year',
                hintText: '2026-27',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _gradeController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _subjectController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _questionCountController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Questions'),
                    validator: _positiveInt,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _durationController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration (min)',
                    ),
                    validator: _positiveInt,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _optionsController,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(
                labelText: 'Answer options',
                helperText: 'Comma-separated, e.g. A, B, C, D',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructionsController,
              enabled: !_isSubmitting,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Instructions (optional)',
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
            : const Text('Create'),
      ),
    ],
  );
}

/// Only [QuestionType.mcqSingle] exists in v1, so the form does not ask.
const QuestionType kDefaultQuestionType = QuestionType.mcqSingle;
