/// Manually add one student (Super Admin only, `manageStudents`) — the
/// counterpart to bulk CSV import (`StudentImportScreen`) for a single
/// child. School, grade and medium are chosen from the selected school's own
/// master data, never typed (requirement §10).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/presentation/widget/school_picker.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_draft.dart';

const List<String> _kSections = <String>['A', 'B', 'C', 'D'];

final class StudentFormScreen extends ConsumerStatefulWidget {
  const StudentFormScreen({super.key});

  @override
  ConsumerState<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends ConsumerState<StudentFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();
  final TextEditingController _electiveController = TextEditingController();
  final TextEditingController _externalCodeController =
      TextEditingController();

  School? _school;
  String? _grade;
  String _section = _kSections.first;
  String? _medium;
  Gender _gender = Gender.notSpecified;
  DateTime? _dateOfBirth;
  bool _submitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _nameController.dispose();
    _languageController.dispose();
    _electiveController.dispose();
    _externalCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 10),
      firstDate: DateTime(now.year - 25),
      lastDate: now,
    );
    if (picked != null) {
      // Midnight UTC on the chosen calendar date, for the same reason the CSV
      // parser normalises: the dedupe key derives from `toUtc()`, and a local
      // midnight would shift the date — and therefore the key — by timezone.
      setState(
        () => _dateOfBirth = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final School? school = _school;
    if (school == null || _grade == null || _medium == null) {
      setState(
        () => _failure = const ValidationFailure(
          userMessage: 'Choose a school, grade and medium first.',
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _failure = null;
    });
    final SessionState session = ref.read(sessionProvider);
    final StudentDraft draft = StudentDraft(
      studentName: _nameController.text.trim(),
      gender: _gender,
      dateOfBirth: _dateOfBirth,
      grade: _grade!,
      section: _section,
      mediumOfInstruction: _medium!,
      language: _languageController.text.trim().isEmpty
          ? _medium!
          : _languageController.text.trim(),
      electiveSubject: _electiveController.text.trim().isEmpty
          ? null
          : _electiveController.text.trim(),
      externalStudentCode: _externalCodeController.text.trim().isEmpty
          ? null
          : _externalCodeController.text.trim(),
    );
    final Result<Student> result = await ref
        .read(studentRepositoryProvider)
        .createStudent(
          draft,
          schoolId: school.schoolId,
          actorUserId: session.session?.user.userId ?? 'unknown',
          actorRole: session.session?.user.role.wireName ?? 'UNKNOWN',
        );
    if (!mounted) {
      return;
    }
    if (result.isFailure) {
      setState(() {
        _submitting = false;
        _failure = result.failureOrNull;
      });
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add student')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_failure != null) ...<Widget>[
                  Text(
                    _failure!.userMessage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SchoolPicker(
                  onSelected: (School school) => setState(() {
                    _school = school;
                    _grade = null;
                    _medium = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'Student name'),
                  validator: (String? v) =>
                      (v ?? '').trim().isEmpty ? 'Enter the student\'s name' : null,
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
                  onChanged: (Gender? g) =>
                      setState(() => _gender = g ?? _gender),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _submitting ? null : _pickDateOfBirth,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date of birth (optional)',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                    child: Text(
                      _dateOfBirth == null
                          ? 'Tap to choose'
                          : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_school != null) ...<Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _grade,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    items: _school!.grades
                        .map(
                          (String g) => DropdownMenuItem<String>(
                            value: g,
                            child: Text('Grade $g'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (String? g) => setState(() => _grade = g),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _section,
                    decoration: const InputDecoration(labelText: 'Section'),
                    items: _kSections
                        .map(
                          (String s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text('Section $s'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (String? s) =>
                        setState(() => _section = s ?? _section),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _medium,
                    decoration: const InputDecoration(
                      labelText: 'Medium of instruction',
                    ),
                    items: _school!.mediumsOfInstruction
                        .map(
                          (String m) => DropdownMenuItem<String>(
                            value: m,
                            child: Text(m),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (String? m) => setState(() => _medium = m),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _languageController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Spoken language (defaults to medium)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _electiveController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Elective subject (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _externalCodeController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'State/UDISE code (optional)',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Add student'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
