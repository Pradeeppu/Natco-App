/// A single student's profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/schools/presentation/controller/school_detail_provider.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/presentation/controller/student_detail_provider.dart';
import 'package:natco_app/features/students/presentation/widget/student_form_dialog.dart';

final class StudentDetailScreen extends ConsumerWidget {
  const StudentDetailScreen({required this.studentId, super.key});

  final String studentId;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) async {
    final school = ref.read(schoolDetailProvider(student.schoolId)).value;
    await showStudentFormDialog(
      context: context,
      existing: student,
      allowedGrades: school?.grades ?? <String>[student.grade],
      allowedMediums: school?.mediumsOfInstruction ?? <String>[
        student.mediumOfInstruction,
      ],
      onSubmit: (StudentDraft draft) async {
        final result = await ref
            .read(studentsRepositoryProvider)
            .updateStudent(
              student.copyWith(
                studentName: draft.studentName,
                gender: draft.gender,
                dateOfBirth: draft.dateOfBirth,
                grade: draft.grade,
                section: draft.section,
                mediumOfInstruction: draft.mediumOfInstruction,
                language: draft.language,
                electiveSubject: draft.electiveSubject,
              ),
            );
        return result.failureOrNull;
      },
    );
    ref.invalidate(studentDetailProvider(studentId));
  }

  Future<void> _toggleActive(WidgetRef ref, Student student) async {
    await ref
        .read(studentsRepositoryProvider)
        .setStudentActive(student.studentId, !student.activeStatus);
    ref.invalidate(studentDetailProvider(studentId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Student?> async = ref.watch(
      studentDetailProvider(studentId),
    );
    final authorization = ref.watch(sessionProvider).authorization;
    final bool canManage = authorization.can(Permission.manageStudents);

    return Scaffold(
      appBar: AppBar(title: const Text('Student')),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace stackTrace) => FailureView(
            failure: error is StudentDetailFailure
                ? error.failure
                : const UnexpectedFailure(),
            onRetry: () => ref.invalidate(studentDetailProvider(studentId)),
          ),
          data: (Student? student) {
            if (student == null) {
              return const EmptyView(
                title: 'Student not found',
                icon: Icons.person_outline,
              );
            }
            return _StudentDetailBody(
              student: student,
              canManage: canManage,
              onEdit: () => _edit(context, ref, student),
              onToggleActive: () => _toggleActive(ref, student),
            );
          },
        ),
      ),
    );
  }
}

final class _StudentDetailBody extends StatelessWidget {
  const _StudentDetailBody({
    required this.student,
    required this.canManage,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Student student;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        CircleAvatar(
          radius: 32,
          child: Text(
            student.studentName.isEmpty
                ? '?'
                : student.studentName[0].toUpperCase(),
            style: theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 12),
        Text(student.studentName, style: theme.textTheme.headlineSmall),
        Text(
          'Grade ${student.grade} · Section ${student.section}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DetailRow(label: 'Gender', value: student.gender.wireName),
                _DetailRow(
                  label: 'Date of birth',
                  value: student.dateOfBirth == null
                      ? '—'
                      : '${student.dateOfBirth!.year}-${student.dateOfBirth!.month.toString().padLeft(2, '0')}-${student.dateOfBirth!.day.toString().padLeft(2, '0')}',
                ),
                _DetailRow(label: 'Medium', value: student.mediumOfInstruction),
                _DetailRow(label: 'Language', value: student.language),
                if (student.electiveSubject != null)
                  _DetailRow(label: 'Elective', value: student.electiveSubject!),
                _DetailRow(
                  label: 'Status',
                  value: student.activeStatus ? 'Active' : 'Inactive',
                ),
              ],
            ),
          ),
        ),
        if (canManage) ...<Widget>[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit student'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onToggleActive,
            icon: Icon(
              student.activeStatus
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            label: Text(student.activeStatus ? 'Deactivate' : 'Reactivate'),
            style: OutlinedButton.styleFrom(
              foregroundColor: student.activeStatus
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

final class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
