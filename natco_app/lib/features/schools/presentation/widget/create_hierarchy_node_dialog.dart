/// A create form shared by State, District and Cluster.
///
/// These three levels have an identical shape — name, code, parent — which is
/// exactly why [GeoNode] models them as one class (see its doc comment). One
/// dialog, parameterised by [HierarchyLevel], is what keeps that shared shape
/// from turning into three near-identical forms.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';

/// The outcome the caller needs: the entered name and code. Persistence is
/// the caller's job — this dialog only collects and validates input.
final class HierarchyNodeDraft {
  const HierarchyNodeDraft({required this.name, required this.code});

  final String name;
  final String code;
}

/// Shows the dialog and returns the draft, or `null` if cancelled.
Future<HierarchyNodeDraft?> showCreateHierarchyNodeDialog({
  required BuildContext context,
  required HierarchyLevel level,
  required Future<Failure?> Function(HierarchyNodeDraft draft) onSubmit,
}) => showDialog<HierarchyNodeDraft>(
  context: context,
  builder: (BuildContext context) =>
      _CreateHierarchyNodeDialog(level: level, onSubmit: onSubmit),
);

final class _CreateHierarchyNodeDialog extends StatefulWidget {
  const _CreateHierarchyNodeDialog({
    required this.level,
    required this.onSubmit,
  });

  final HierarchyLevel level;
  final Future<Failure?> Function(HierarchyNodeDraft draft) onSubmit;

  @override
  State<_CreateHierarchyNodeDialog> createState() =>
      _CreateHierarchyNodeDialogState();
}

class _CreateHierarchyNodeDialogState
    extends State<_CreateHierarchyNodeDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });
    final HierarchyNodeDraft draft = HierarchyNodeDraft(
      name: _nameController.text.trim(),
      code: _codeController.text.trim(),
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Add ${widget.level.displayName.toLowerCase()}'),
    content: Form(
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
            decoration: InputDecoration(
              labelText: '${widget.level.displayName} name',
            ),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _codeController,
            enabled: !_isSubmitting,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: '${widget.level.displayName} code',
            ),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? 'Required' : null,
          ),
        ],
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
