/// Create an assessment.
///
/// Only the paper's own shape is set here — name, grade, subject, how many
/// questions, what each is worth. The answer key and the schools sitting it
/// are separate, deliberate steps, because both are decisions somebody else
/// often makes and both are audited on their own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessments/data/service/demo_assessment_data.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';

final class AssessmentFormScreen extends ConsumerStatefulWidget {
  const AssessmentFormScreen({super.key});

  @override
  ConsumerState<AssessmentFormScreen> createState() =>
      _AssessmentFormScreenState();
}

class _AssessmentFormScreenState extends ConsumerState<AssessmentFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _grade = TextEditingController();
  final TextEditingController _questions = TextEditingController(text: '50');
  final TextEditingController _marks = TextEditingController(text: '1');
  final TextEditingController _year = TextEditingController(
    text: DemoAssessmentIds.academicYear,
  );
  final TextEditingController _description = TextEditingController();

  bool _saving = false;
  Failure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _grade.dispose();
    _questions.dispose();
    _marks.dispose();
    _year.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }
    setState(() {
      _saving = true;
      _failure = null;
    });

    final DateTime now = ref.read(clockProvider).nowUtc();
    final Assessment assessment = Assessment(
      assessmentId: ref.read(idGeneratorProvider).newId(),
      assessmentName: _name.text.trim(),
      academicYear: _year.text.trim(),
      grade: _grade.text.trim(),
      subject: _subject.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      totalQuestions: int.parse(_questions.text.trim()),
      marksPerQuestion: double.parse(_marks.text.trim()),
      // Always starts as a draft. There is no "create it published" path: an
      // assessment with no answer key cannot legally be published, and
      // offering the shortcut would only produce a rejection.
      status: AssessmentStatus.draft,
      omrTemplateId: DemoAssessmentIds.templateId,
      createdBy: actor.userId,
      createdAt: now,
      updatedAt: now,
    );

    final Result<Assessment> result = await ref
        .read(assessmentRepositoryProvider)
        .createAssessment(
          assessment,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    switch (result) {
      case Success<Assessment>():
        await ref.read(assessmentListControllerProvider.notifier).refresh();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft created. Set its answer key next.'),
          ),
        );
        Navigator.of(context).pop();
      case FailureResult<Assessment>(:final Failure failure):
        setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Failure? failure = _failure;
    return Scaffold(
      appBar: AppBar(title: const Text('New assessment')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              if (failure != null) ...<Widget>[
                InfoBanner(
                  message: failure.userMessage,
                  icon: Icons.error_outline,
                  isWarning: true,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Assessment name',
                  helperText: 'For example, Grade 5 Numeracy - Baseline',
                  prefixIcon: Icon(Icons.assignment_outlined),
                ),
                validator: _required('Give the assessment a name.'),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _grade,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Grade'),
                      validator: _required('Enter the grade.'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _subject,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Subject'),
                      validator: _required('Enter the subject.'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _year,
                decoration: const InputDecoration(
                  labelText: 'Academic year',
                  helperText: 'For example, 2026-27',
                ),
                validator: _required('Enter the academic year.'),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _questions,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Questions',
                      ),
                      validator: (String? value) {
                        final int? count = int.tryParse(
                          (value ?? '').trim(),
                        );
                        if (count == null || count < 1) {
                          return 'At least 1.';
                        }
                        // The OMR template's bubble grid is what caps this;
                        // a paper longer than the sheet cannot be scanned.
                        if (count > 200) {
                          return 'At most 200.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _marks,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Marks each',
                      ),
                      validator: (String? value) {
                        final double? marks = double.tryParse(
                          (value ?? '').trim(),
                        );
                        return marks == null || marks <= 0
                            ? 'More than 0.'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Creating...' : 'Create draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? Function(String?) _required(String message) =>
      (String? value) =>
          (value == null || value.trim().isEmpty) ? message : null;
}
