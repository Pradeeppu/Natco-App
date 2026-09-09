/// One school: its place in the hierarchy, its grades and mediums, and
/// (Super Admin) inline editing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

final class SchoolDetailScreen extends ConsumerStatefulWidget {
  const SchoolDetailScreen({required this.schoolId, super.key});

  final String schoolId;

  @override
  ConsumerState<SchoolDetailScreen> createState() =>
      _SchoolDetailScreenState();
}

class _SchoolDetailScreenState extends ConsumerState<SchoolDetailScreen> {
  Result<School>? _result;
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _pincodeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _addressController = TextEditingController();
    _pincodeController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Result<School> result = await ref
        .read(schoolHierarchyRepositoryProvider)
        .getSchool(widget.schoolId);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = result;
      final School? school = result.valueOrNull;
      if (school != null) {
        _nameController.text = school.schoolName;
        _addressController.text = school.address ?? '';
        _pincodeController.text = school.pincode ?? '';
      }
    });
  }

  Future<void> _save(School current) async {
    setState(() => _saving = true);
    final SessionState session = ref.read(sessionProvider);
    final School updated = current.copyWith(
      schoolName: _nameController.text.trim(),
      address: _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      pincode: _pincodeController.text.trim().isEmpty
          ? null
          : _pincodeController.text.trim(),
    );
    final Result<School> result = await ref
        .read(schoolHierarchyRepositoryProvider)
        .updateSchool(
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
    final Result<School>? result = _result;
    final SessionState session = ref.watch(sessionProvider);
    final bool canManage = session.authorization.can(Permission.manageSchools);

    return Scaffold(
      appBar: AppBar(
        title: const Text('School'),
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
          FailureResult<School>(:final Failure failure) => FailureView(
            failure: failure,
            onRetry: _load,
          ),
          Success<School>(:final School value) => _editing
              ? _editForm(value)
              : _viewBody(value),
        },
      ),
    );
  }

  Widget _viewBody(School school) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(school.schoolName, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          school.schoolCode,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (school.address != null) ...<Widget>[
          _InfoRow(icon: Icons.location_on_outlined, label: school.address!),
          const SizedBox(height: 8),
        ],
        if (school.pincode != null) ...<Widget>[
          _InfoRow(icon: Icons.local_post_office_outlined, label: school.pincode!),
          const SizedBox(height: 8),
        ],
        _InfoRow(
          icon: Icons.grade_outlined,
          label: 'Grades: ${school.grades.join(', ')}',
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.translate_outlined,
          label: 'Mediums: ${school.mediumsOfInstruction.join(', ')}',
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => context.push(
            '${RoutePaths.students}?schoolId=${school.schoolId}',
          ),
          icon: const Icon(Icons.groups_outlined),
          label: const Text('View students'),
        ),
      ],
    );
  }

  Widget _editForm(School school) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _nameController,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'School name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressController,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pincodeController,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Pincode'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : () => _save(school),
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
