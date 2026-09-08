/// A single school: its identity, its grades and mediums, and the actions a
/// permitted user may take on it.
///
/// Ancestry (state/district/cluster names) is deliberately not shown: those
/// are stored on `School` as ids, and resolving them to names here would need
/// three extra lookups for a detail screen whose primary purpose is
/// "manage this school" and "see its students". Worth adding once a screen
/// actually needs to display the chain rather than just enforce it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/presentation/controller/school_detail_provider.dart';
import 'package:natco_app/features/schools/presentation/controller/schools_browser_controller.dart';
import 'package:natco_app/features/schools/presentation/widget/school_form_dialog.dart';

final class SchoolDetailScreen extends ConsumerWidget {
  const SchoolDetailScreen({required this.schoolId, super.key});

  final String schoolId;

  Future<void> _edit(BuildContext context, WidgetRef ref, School school) async {
    await showSchoolFormDialog(
      context: context,
      existing: school,
      onSubmit: (SchoolDraft draft) async {
        final result = await ref
            .read(schoolsRepositoryProvider)
            .updateSchool(
              school.copyWith(
                schoolName: draft.schoolName,
                grades: draft.grades,
                mediumsOfInstruction: draft.mediumsOfInstruction,
                address: draft.address,
                pincode: draft.pincode,
              ),
            );
        return result.failureOrNull;
      },
    );
    ref.invalidate(schoolDetailProvider(schoolId));
  }

  Future<void> _toggleActive(WidgetRef ref, School school) async {
    await ref
        .read(schoolsRepositoryProvider)
        .setSchoolActive(school.schoolId, !school.isActive);
    ref.invalidate(schoolDetailProvider(schoolId));
    // The browse list may currently be showing this school; keep it in sync
    // rather than leaving a stale active/inactive state on screen.
    await ref.read(schoolsBrowserProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<School?> async = ref.watch(schoolDetailProvider(schoolId));
    final authorization = ref.watch(sessionProvider).authorization;
    final bool canManage = authorization.can(Permission.manageSchools);

    return Scaffold(
      appBar: AppBar(title: const Text('School')),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace stackTrace) => FailureView(
            failure: error is SchoolDetailFailure
                ? error.failure
                // A framework-level error unrelated to the repository
                // call: no specific Failure to unwrap, so fall back to the
                // generic one rather than fabricating a more specific reason.
                : const UnexpectedFailure(),
            onRetry: () => ref.invalidate(schoolDetailProvider(schoolId)),
          ),
          data: (School? school) {
            if (school == null) {
              return const EmptyView(
                title: 'School not found',
                icon: Icons.school_outlined,
              );
            }
            return _SchoolDetailBody(
              school: school,
              canManage: canManage,
              canViewStudents: authorization.can(Permission.viewStudents),
              onEdit: () => _edit(context, ref, school),
              onToggleActive: () => _toggleActive(ref, school),
              onViewStudents: () => context.go(
                Uri(
                  path: RoutePaths.students,
                  queryParameters: <String, String>{
                    'schoolId': school.schoolId,
                  },
                ).toString(),
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _SchoolDetailBody extends StatelessWidget {
  const _SchoolDetailBody({
    required this.school,
    required this.canManage,
    required this.canViewStudents,
    required this.onEdit,
    required this.onToggleActive,
    required this.onViewStudents,
  });

  final School school;
  final bool canManage;
  final bool canViewStudents;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onViewStudents;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                school.schoolName,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            StatusChip(
              label: school.isActive ? 'Active' : 'Inactive',
              tone: school.isActive ? StatusTone.success : StatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Code ${school.schoolCode}',
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
                _DetailRow(label: 'Grades', value: school.grades.join(', ')),
                _DetailRow(
                  label: 'Mediums',
                  value: school.mediumsOfInstruction.join(', '),
                ),
                if (school.address != null)
                  _DetailRow(label: 'Address', value: school.address!),
                if (school.pincode != null)
                  _DetailRow(label: 'Pincode', value: school.pincode!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (canViewStudents)
          OutlinedButton.icon(
            onPressed: onViewStudents,
            icon: const Icon(Icons.groups_outlined),
            label: const Text('View students'),
          ),
        if (canManage) ...<Widget>[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit school'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onToggleActive,
            icon: Icon(
              school.isActive
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            label: Text(school.isActive ? 'Deactivate' : 'Reactivate'),
            style: OutlinedButton.styleFrom(
              foregroundColor: school.isActive ? theme.colorScheme.error : null,
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
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
