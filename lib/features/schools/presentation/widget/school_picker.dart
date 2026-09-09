/// A reusable "pick a school" selector.
///
/// Requirement §10 forbids ever letting a value from the geographic
/// hierarchy be free-typed — it must always come from a selector backed by
/// master data. This is that selector for School specifically, used by the
/// Students screen's school filter and `StudentFormScreen` today, and
/// intended for `features/assessments`/`assessment_sessions` in later
/// phases: it lives under `features/schools` (never imports downward into
/// those features) so they can import it with no circular dependency.
///
/// Deliberately self-contained (its own search state, not the shared
/// `SchoolListController`): that controller is a single app-wide instance,
/// and a modal picker opened from another screen must not share — and
/// silently reset — whatever list state that screen already has.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';

final class SchoolPicker extends ConsumerStatefulWidget {
  const SchoolPicker({
    required this.onSelected,
    this.initialSchoolId,
    this.label = 'School',
    super.key,
  });

  final ValueChanged<School> onSelected;
  final String? initialSchoolId;
  final String label;

  @override
  ConsumerState<SchoolPicker> createState() => _SchoolPickerState();
}

class _SchoolPickerState extends ConsumerState<SchoolPicker> {
  School? _selected;
  bool _resolvingInitial = false;

  @override
  void initState() {
    super.initState();
    final String? id = widget.initialSchoolId;
    if (id != null) {
      _resolvingInitial = true;
      unawaited(_resolveInitial(id));
    }
  }

  Future<void> _resolveInitial(String schoolId) async {
    final result = await ref
        .read(schoolHierarchyRepositoryProvider)
        .getSchool(schoolId);
    if (!mounted) {
      return;
    }
    setState(() {
      _resolvingInitial = false;
      _selected = result.valueOrNull;
    });
  }

  Future<void> _openSheet() async {
    final School? picked = await showModalBottomSheet<School>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => const _SchoolSearchSheet(),
    );
    if (picked != null && mounted) {
      setState(() => _selected = picked);
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: _openSheet,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.school_outlined),
          suffixIcon: const Icon(Icons.unfold_more),
        ),
        child: _resolvingInitial
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                _selected?.schoolName ?? 'Tap to choose a school',
                style: _selected == null
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyMedium,
              ),
      ),
    );
  }
}

final class _SchoolSearchSheet extends ConsumerStatefulWidget {
  const _SchoolSearchSheet();

  @override
  ConsumerState<_SchoolSearchSheet> createState() => _SchoolSearchSheetState();
}

class _SchoolSearchSheetState extends ConsumerState<_SchoolSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  Failure? _failure;
  List<School> _results = const <School>[];

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final SessionState session = ref.read(sessionProvider);
    final AccessScope scope =
        session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
    final result = await ref
        .read(schoolHierarchyRepositoryProvider)
        .listSchools(scope: scope, query: query, pageSize: 30);
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      result.fold(
        onSuccess: (page) => _results = page.items,
        onFailure: (Failure f) => _failure = f,
      );
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_search(value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search school by name or code',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onChanged,
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const LoadingView();
    }
    final Failure? failure = _failure;
    if (failure != null) {
      return FailureView(
        failure: failure,
        onRetry: () => unawaited(_search(_controller.text)),
      );
    }
    if (_results.isEmpty) {
      return const EmptyView(
        title: 'No schools found',
        message: 'Try a different name or code.',
        icon: Icons.school_outlined,
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (BuildContext context, int index) {
        final School school = _results[index];
        return ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(school.schoolName),
          subtitle: Text(school.schoolCode),
          onTap: () => Navigator.of(context).pop(school),
        );
      },
    );
  }
}
