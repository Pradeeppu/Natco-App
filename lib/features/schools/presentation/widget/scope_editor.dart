/// Builds an [AccessScope] by picking real hierarchy rows.
///
/// Requirement §10 forbids free-typing anything from the geographic
/// hierarchy, and a scope is nothing *but* hierarchy references — so a text
/// field of comma-separated ids would be the worst possible version of this
/// screen. Every id here comes from a search over master data the caller can
/// already see.
///
/// Lives under `features/schools` alongside [SchoolPicker], so
/// `features/users` (and later phases) can import it downward with no circular
/// dependency.
library;

import 'dart:async';

// `Page` is hidden because Flutter's navigator declares one too, and the
// paginated `Page<T>` record type below is the one this file means.
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';

/// One picked hierarchy row: enough to store, and enough to show.
typedef ScopeEntity = ({String id, String name});

final class ScopeEditor extends ConsumerStatefulWidget {
  const ScopeEditor({
    required this.allowedLevels,
    required this.onChanged,
    this.initialScope,
    this.showGradeSections = false,
    super.key,
  });

  /// Levels the *actor* may hand out, in widening order. A Supervisor is
  /// given `[ScopeLevel.school]` only; a Super Admin gets the full list.
  /// Offering a level the policy would then refuse is how a form teaches
  /// someone to distrust it.
  final List<ScopeLevel> allowedLevels;

  final ValueChanged<AccessScope> onChanged;
  final AccessScope? initialScope;

  /// Whether to offer grade-section narrowing. Only meaningful for a PST
  /// Teacher, who is assigned to 5-A and must not open 5-B even in their own
  /// school (Critical Rule 10).
  final bool showGradeSections;

  @override
  ConsumerState<ScopeEditor> createState() => _ScopeEditorState();
}

class _ScopeEditorState extends ConsumerState<ScopeEditor> {
  late ScopeLevel _level;
  final Map<String, String> _picked = <String, String>{};
  final Set<GradeSection> _gradeSections = <GradeSection>{};

  @override
  void initState() {
    super.initState();
    final AccessScope? initial = widget.initialScope;
    _level = initial != null && widget.allowedLevels.contains(initial.level)
        ? initial.level
        : widget.allowedLevels.last;
    if (initial != null) {
      for (final String id in initial.definingIds) {
        // The name is filled in when the row is picked; a scope loaded from
        // storage shows the id until then rather than blocking the form on a
        // lookup per entry.
        _picked[id] = id;
      }
      _gradeSections.addAll(initial.gradeSections);
    }
  }

  void _emit() {
    final Set<String> ids = _picked.keys.toSet();
    widget.onChanged(
      AccessScope(
        level: _level,
        stateIds: _level == ScopeLevel.state ? ids : const <String>{},
        districtIds: _level == ScopeLevel.district ? ids : const <String>{},
        clusterIds: _level == ScopeLevel.cluster ? ids : const <String>{},
        schoolIds: _level == ScopeLevel.school ? ids : const <String>{},
        gradeSections: _level == ScopeLevel.school
            ? Set<GradeSection>.of(_gradeSections)
            : const <GradeSection>{},
      ),
    );
  }

  Future<void> _add() async {
    final ScopeEntity? picked = await showModalBottomSheet<ScopeEntity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HierarchySearchSheet(level: _level),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _picked[picked.id] = picked.name);
    _emit();
  }

  Future<void> _addGradeSection() async {
    final GradeSection? picked = await showDialog<GradeSection>(
      context: context,
      builder: (_) => const _GradeSectionDialog(),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _gradeSections.add(picked));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.allowedLevels.length > 1)
          DropdownButtonFormField<ScopeLevel>(
            initialValue: _level,
            // Without this, the selected item sizes to its own intrinsic
            // width and can collide with the dropdown arrow on a narrow
            // screen — `isExpanded` makes it fill the field instead.
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Level of access',
              prefixIcon: Icon(Icons.layers_outlined),
            ),
            items: widget.allowedLevels
                .map(
                  (ScopeLevel level) => DropdownMenuItem<ScopeLevel>(
                    value: level,
                    child: Text(_levelLabel(level)),
                  ),
                )
                .toList(growable: false),
            onChanged: (ScopeLevel? value) {
              if (value == null || value == _level) {
                return;
              }
              // Ids from the previous level mean nothing at the new one, and
              // silently keeping them would grant reach nobody chose.
              setState(() {
                _level = value;
                _picked.clear();
                _gradeSections.clear();
              });
              _emit();
            },
          )
        else
          Text(
            _levelLabel(_level),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 12),
        if (_picked.isEmpty)
          Text(
            'Nothing selected yet. This person would not be able to see '
            'anything.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _picked.entries
                .map(
                  (MapEntry<String, String> entry) => InputChip(
                    label: Text(entry.value),
                    onDeleted: () {
                      setState(() => _picked.remove(entry.key));
                      _emit();
                    },
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text('Add ${_levelNoun(_level)}'),
          ),
        ),
        if (widget.showGradeSections && _level == ScopeLevel.school) ...<Widget>[
          const Divider(height: 32),
          Text('Classes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            _gradeSections.isEmpty
                ? 'Every class in the schools above. Add one or more to limit '
                      'this person to specific classes.'
                : 'Limited to these classes only.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_gradeSections.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _gradeSections
                  .map(
                    (GradeSection gs) => InputChip(
                      label: Text(gs.displayName),
                      onDeleted: () {
                        setState(() => _gradeSections.remove(gs));
                        _emit();
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addGradeSection,
              icon: const Icon(Icons.add),
              label: const Text('Add class'),
            ),
          ),
        ],
      ],
    );
  }

  static String _levelLabel(ScopeLevel level) => switch (level) {
    ScopeLevel.global => 'Entire programme',
    ScopeLevel.state => 'Specific states',
    ScopeLevel.district => 'Specific districts',
    ScopeLevel.cluster => 'Specific clusters',
    ScopeLevel.school => 'Specific schools',
  };

  static String _levelNoun(ScopeLevel level) => switch (level) {
    ScopeLevel.global => 'everything',
    ScopeLevel.state => 'state',
    ScopeLevel.district => 'district',
    ScopeLevel.cluster => 'cluster',
    ScopeLevel.school => 'school',
  };
}

/// Searches one level of the hierarchy, within the caller's own scope.
final class _HierarchySearchSheet extends ConsumerStatefulWidget {
  const _HierarchySearchSheet({required this.level});

  final ScopeLevel level;

  @override
  ConsumerState<_HierarchySearchSheet> createState() =>
      _HierarchySearchSheetState();
}

class _HierarchySearchSheetState
    extends ConsumerState<_HierarchySearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  Failure? _failure;
  List<ScopeEntity> _results = const <ScopeEntity>[];

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
    final repository = ref.read(schoolHierarchyRepositoryProvider);

    // The caller's own scope bounds every one of these queries, so a
    // Supervisor searching for a school to assign can only find schools they
    // already reach.
    final Result<List<ScopeEntity>> result = switch (widget.level) {
      ScopeLevel.global => ok(const <ScopeEntity>[]),
      ScopeLevel.state => (await repository.listStates(
        scope: scope,
        query: query,
        pageSize: 30,
      )).map(
        (Page<StateEntity> page) => page.items
            .map((StateEntity e) => (id: e.stateId, name: e.stateName))
            .toList(growable: false),
      ),
      ScopeLevel.district => (await repository.listDistricts(
        scope: scope,
        query: query,
        pageSize: 30,
      )).map(
        (Page<District> page) => page.items
            .map((District e) => (id: e.districtId, name: e.districtName))
            .toList(growable: false),
      ),
      ScopeLevel.cluster => (await repository.listClusters(
        scope: scope,
        query: query,
        pageSize: 30,
      )).map(
        (Page<Cluster> page) => page.items
            .map((Cluster e) => (id: e.clusterId, name: e.clusterName))
            .toList(growable: false),
      ),
      ScopeLevel.school => (await repository.listSchools(
        scope: scope,
        query: query,
        pageSize: 30,
      )).map(
        (Page<School> page) => page.items
            .map((School e) => (id: e.schoolId, name: e.schoolName))
            .toList(growable: false),
      ),
    };

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      result.fold(
        onSuccess: (List<ScopeEntity> items) => _results = items,
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
                    labelText: 'Search by name',
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
        title: 'Nothing found',
        message: 'Try a different name.',
        icon: Icons.search_off_outlined,
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (BuildContext context, int index) {
        final ScopeEntity entity = _results[index];
        return ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: Text(entity.name),
          onTap: () => Navigator.of(context).pop(entity),
        );
      },
    );
  }
}

/// Grade and section, entered as two short fields rather than one free-text
/// "5-A" — the wire form is an implementation detail, and a typo in it would
/// silently produce a scope that matches nothing.
final class _GradeSectionDialog extends StatefulWidget {
  const _GradeSectionDialog();

  @override
  State<_GradeSectionDialog> createState() => _GradeSectionDialogState();
}

class _GradeSectionDialogState extends State<_GradeSectionDialog> {
  final TextEditingController _grade = TextEditingController();
  final TextEditingController _section = TextEditingController();

  @override
  void dispose() {
    _grade.dispose();
    _section.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a class'),
      content: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _grade,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Grade'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _section,
              decoration: const InputDecoration(labelText: 'Section'),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final String grade = _grade.text.trim();
            final String section = _section.text.trim();
            if (grade.isEmpty || section.isEmpty) {
              return;
            }
            Navigator.of(
              context,
            ).pop(GradeSection(grade: grade, section: section));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
