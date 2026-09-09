/// One student: profile, and (Super Admin) inline editing. Academic-year
/// enrollment history and assessment results are phase 3/4 and phase 8
/// (docs/08-mvp-implementation-plan.md) — this shows current master data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

final class StudentDetailScreen extends ConsumerStatefulWidget {
  const StudentDetailScreen({required this.studentId, super.key});

  final String studentId;

  @override
  ConsumerState<StudentDetailScreen> createState() =>
      _StudentDetailScreenState();
}

class _StudentDetailScreenState extends ConsumerState<StudentDetailScreen> {
  Result<Student>? _result;
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _nameController;
  late final TextEditingController _electiveController;
  Gender _gender = Gender.notSpecified;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _electiveController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _electiveController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Result<Student> result = await ref
        .read(studentRepositoryProvider)
        .getStudent(widget.studentId);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = result;
      final Student? student = result.valueOrNull;
      if (student != null) {
        _nameController.text = student.studentName;
        _electiveController.text = student.electiveSubject ?? '';
        _gender = student.gender;
      }
    });
  }

  Future<void> _save(Student current) async {
    setState(() => _saving = true);
    final SessionState session = ref.read(sessionProvider);
    final Student updated = current.copyWith(
      studentName: _nameController.text.trim(),
      gender: _gender,
      electiveSubject: _electiveController.text.trim().isEmpty
          ? null
          : _electiveController.text.trim(),
    );
    final Result<Student> result = await ref
        .read(studentRepositoryProvider)
        .updateStudent(
          updated,
          actorUserId: session.session?.user.userId ?? 'unknown',
          actorRole: session.session?.user.role.wireName ?? 'UNKNOWN',
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _result = result;
      _editing = result.isFailure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Result<Student>? result = _result;
    final SessionState session = ref.watch(sessionProvider);
    final bool canManage = session.authorization.can(
      Permission.manageStudents,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student'),
        actions: <Widget>[
          if (canManage && result?.valueOrNull != null)
            IconButton(
              icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
              tooltip: _editing ? 'Cancel' : 'Edit',
              onPressed: () => setState(() => _editing = !_editing),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (result) {
          null => const LoadingView(),
          FailureResult<Student>(:final Failure failure) => FailureView(
            failure: failure,
            onRetry: _load,
          ),
          Success<Student>(:final Student value) =>
            _editing ? _editForm(value) : _viewBody(value),
        },
      ),
    );
  }

  Widget _viewBody(Student student) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(student.studentName, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Grade ${student.grade} - Section ${student.section}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _InfoRow(icon: Icons.translate_outlined, label: student.mediumOfInstruction),
        const SizedBox(height: 8),
        _InfoRow(icon: Icons.language_outlined, label: student.language),
        if (student.electiveSubject != null) ...<Widget>[
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.menu_book_outlined, label: student.electiveSubject!),
        ],
        if (student.externalStudentCode != null) ...<Widget>[
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.badge_outlined, label: student.externalStudentCode!),
        ],
      ],
    );
  }

  Widget _editForm(Student student) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _nameController,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Student name'),
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
          onChanged: _saving
              ? null
              : (Gender? g) => setState(() => _gender = g ?? _gender),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _electiveController,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Elective subject (optional)'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : () => _save(student),
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Save changes'),
        ),
      ],
    );
  }
}

final class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
