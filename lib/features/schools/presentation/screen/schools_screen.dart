/// Schools: the State → District → Cluster → School hierarchy browser
/// (requirement §10, §27), plus a scope-wide "search a school by name"
/// shortcut.
///
/// A user's landing level matches their own scope — a cluster-scoped
/// Supervisor lands directly on their clusters, not an empty state picker
/// (docs/04-security-model.md §31: "Supervisors get no implicit reach", so
/// there is nothing useful to show them above their own scope anyway).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/cluster.dart';
import 'package:natco_app/features/schools/domain/entity/district.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/domain/entity/state_entity.dart';
import 'package:natco_app/features/schools/presentation/controller/hierarchy_providers.dart';
import 'package:natco_app/features/schools/presentation/controller/school_list_controller.dart';

enum _Level { states, districts, clusters, schools }

_Level _initialLevel(AccessScope scope) => switch (scope.level) {
  ScopeLevel.global || ScopeLevel.state => _Level.states,
  ScopeLevel.district => _Level.districts,
  ScopeLevel.cluster => _Level.clusters,
  ScopeLevel.school => _Level.schools,
};

final class SchoolsScreen extends ConsumerStatefulWidget {
  const SchoolsScreen({super.key});

  @override
  ConsumerState<SchoolsScreen> createState() => _SchoolsScreenState();
}

class _SchoolsScreenState extends ConsumerState<SchoolsScreen> {
  late _Level _level;
  StateEntity? _selectedState;
  District? _selectedDistrict;
  Cluster? _selectedCluster;
  bool _searching = false;
  bool _initialised = false;

  void _ensureInitialised(AccessScope scope) {
    if (_initialised) {
      return;
    }
    _initialised = true;
    _level = _initialLevel(scope);
    if (_level == _Level.schools) {
      // Already at the bottom level: nothing to select down into further.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(schoolListControllerProvider.notifier).setClusterFilter(null);
      });
    }
  }

  void _openState(StateEntity state) {
    setState(() {
      _selectedState = state;
      _level = _Level.districts;
    });
  }

  void _openDistrict(District district) {
    setState(() {
      _selectedDistrict = district;
      _level = _Level.clusters;
    });
  }

  void _openCluster(Cluster cluster) {
    setState(() {
      _selectedCluster = cluster;
      _level = _Level.schools;
    });
    ref
        .read(schoolListControllerProvider.notifier)
        .setClusterFilter(cluster.clusterId);
  }

  void _back() {
    setState(() {
      switch (_level) {
        case _Level.states:
          break;
        case _Level.districts:
          _level = _Level.states;
          _selectedState = null;
        case _Level.clusters:
          _level = _Level.districts;
          _selectedDistrict = null;
        case _Level.schools:
          _level = _Level.clusters;
          _selectedCluster = null;
          ref.read(schoolListControllerProvider.notifier).setClusterFilter(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final AccessScope scope =
        session.authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
    _ensureInitialised(scope);
    final Authorization authorization = session.authorization;

    final bool canGoBack = !_searching && _level != _initialLevel(scope);

    return Scaffold(
      appBar: AppBar(
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _back,
              )
            : null,
        title: Text(_searching ? 'Search schools' : _titleFor(_level)),
        actions: <Widget>[
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Close search' : 'Search schools',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                ref.read(schoolListControllerProvider.notifier).setQuery('');
              }
            }),
          ),
        ],
      ),
      floatingActionButton: _fab(authorization),
      body: SafeArea(
        child: _searching
            ? _SearchBody(onQueryChanged: (String q) {
                ref.read(schoolListControllerProvider.notifier).setQuery(q);
              })
            : _hierarchyBody(),
      ),
    );
  }

  String _titleFor(_Level level) => switch (level) {
    _Level.states => 'Schools',
    _Level.districts => _selectedState?.stateName ?? 'Districts',
    _Level.clusters => _selectedDistrict?.districtName ?? 'Clusters',
    _Level.schools => _selectedCluster?.clusterName ?? 'Schools',
  };

  Widget? _fab(Authorization authorization) {
    final (Permission permission, VoidCallback? onPressed, String label) =
        switch (_level) {
          _Level.states => (
            Permission.manageStates,
            () => _showHierarchyForm(_HierarchyFormKind.state),
            'Add state',
          ),
          _Level.districts => (
            Permission.manageDistricts,
            _selectedState == null
                ? null
                : () => _showHierarchyForm(_HierarchyFormKind.district),
            'Add district',
          ),
          _Level.clusters => (
            Permission.manageClusters,
            _selectedDistrict == null
                ? null
                : () => _showHierarchyForm(_HierarchyFormKind.cluster),
            'Add cluster',
          ),
          _Level.schools => (
            Permission.manageSchools,
            () => context.push(RoutePaths.schoolNew),
            'Add school',
          ),
        };
    if (_searching || !authorization.can(permission) || onPressed == null) {
      return null;
    }
    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
    );
  }

  Future<void> _showHierarchyForm(_HierarchyFormKind kind) async {
    final bool? created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _HierarchyEntityFormSheet(
        kind: kind,
        parentStateId: _selectedState?.stateId,
        parentDistrictId: _selectedDistrict?.districtId,
      ),
    );
    if (created ?? false) {
      _invalidateCurrentLevel();
    }
  }

  void _invalidateCurrentLevel() {
    switch (_level) {
      case _Level.states:
        ref.invalidate(statesProvider);
      case _Level.districts:
        ref.invalidate(districtsProvider(_selectedState?.stateId));
      case _Level.clusters:
        ref.invalidate(clustersProvider(_selectedDistrict?.districtId));
      case _Level.schools:
        break;
    }
  }

  Widget _hierarchyBody() {
    switch (_level) {
      case _Level.states:
        return _AsyncEntityList<StateEntity>(
          value: ref.watch(statesProvider),
          onRetry: () => ref.invalidate(statesProvider),
          itemBuilder: (StateEntity s) => ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text(s.stateName),
            subtitle: Text(s.stateCode),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openState(s),
          ),
          emptyTitle: 'No states yet',
        );
      case _Level.districts:
        return _AsyncEntityList<District>(
          value: ref.watch(districtsProvider(_selectedState?.stateId)),
          onRetry: () =>
              ref.invalidate(districtsProvider(_selectedState?.stateId)),
          itemBuilder: (District d) => ListTile(
            leading: const Icon(Icons.location_city_outlined),
            title: Text(d.districtName),
            subtitle: Text(d.districtCode),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDistrict(d),
          ),
          emptyTitle: 'No districts yet',
        );
      case _Level.clusters:
        return _AsyncEntityList<Cluster>(
          value: ref.watch(clustersProvider(_selectedDistrict?.districtId)),
          onRetry: () =>
              ref.invalidate(clustersProvider(_selectedDistrict?.districtId)),
          itemBuilder: (Cluster c) => ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text(c.clusterName),
            subtitle: Text(c.clusterCode),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openCluster(c),
          ),
          emptyTitle: 'No clusters yet',
        );
      case _Level.schools:
        return const _PagedSchoolList();
    }
  }
}

enum _HierarchyFormKind { state, district, cluster }

/// Renders one already-watched level of the hierarchy.
///
/// Takes the resolved [AsyncValue] rather than the provider itself: Riverpod 3
/// does not export `ProviderListenable` from `package:flutter_riverpod`, so a
/// widget cannot name a provider as a field type. Watching in the parent and
/// passing the value down is the simpler shape anyway.
final class _AsyncEntityList<T> extends StatelessWidget {
  const _AsyncEntityList({
    required this.value,
    required this.itemBuilder,
    required this.emptyTitle,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<Result<List<T>>> value;
  final Widget Function(T item) itemBuilder;
  final String emptyTitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const LoadingView(),
      // Retained for an unexpected throw. An *expected* failure arrives as
      // data carrying a `FailureResult` — see `hierarchy_providers.dart`.
      error: (Object error, StackTrace _) =>
          FailureView(failure: asFailure(error), onRetry: onRetry),
      data: (Result<List<T>> result) => result.fold(
        onFailure: (Failure failure) =>
            FailureView(failure: failure, onRetry: onRetry),
        onSuccess: (List<T> items) {
          if (items.isEmpty) {
            return EmptyView(
              title: emptyTitle,
              icon: Icons.folder_open_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) =>
                itemBuilder(items[index]),
          );
        },
      ),
    );
  }
}

final class _PagedSchoolList extends ConsumerStatefulWidget {
  const _PagedSchoolList();

  @override
  ConsumerState<_PagedSchoolList> createState() => _PagedSchoolListState();
}

class _PagedSchoolListState extends ConsumerState<_PagedSchoolList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(schoolListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedListState<School>> value = ref.watch(
      schoolListControllerProvider,
    );
    return value.when(
      loading: () => const LoadingView(),
      error: (Object error, StackTrace _) => FailureView(
        failure: asFailure(error),
        onRetry: () =>
            ref.read(schoolListControllerProvider.notifier).refresh(),
      ),
      data: (PagedListState<School> state) {
        final Failure? failure = state.failure;
        if (failure != null) {
          return FailureView(
            failure: failure,
            onRetry: () =>
                ref.read(schoolListControllerProvider.notifier).refresh(),
          );
        }
        if (state.items.isEmpty) {
          return const EmptyView(
            title: 'No schools here yet',
            icon: Icons.school_outlined,
          );
        }
        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: state.items.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            if (index >= state.items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              );
            }
            final School school = state.items[index];
            return ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(school.schoolName),
              subtitle: Text(school.schoolCode),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                RoutePaths.of(RoutePaths.schoolDetail, <String, String>{
                  'schoolId': school.schoolId,
                }),
              ),
            );
          },
        );
      },
    );
  }
}

final class _SearchBody extends ConsumerStatefulWidget {
  const _SearchBody({required this.onQueryChanged});

  final ValueChanged<String> onQueryChanged;

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search by name or code',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: widget.onQueryChanged,
          ),
        ),
        const Expanded(child: _PagedSchoolList()),
      ],
    );
  }
}

final class _HierarchyEntityFormSheet extends ConsumerStatefulWidget {
  const _HierarchyEntityFormSheet({
    required this.kind,
    this.parentStateId,
    this.parentDistrictId,
  });

  final _HierarchyFormKind kind;
  final String? parentStateId;
  final String? parentDistrictId;

  @override
  ConsumerState<_HierarchyEntityFormSheet> createState() =>
      _HierarchyEntityFormSheetState();
}

class _HierarchyEntityFormSheetState
    extends ConsumerState<_HierarchyEntityFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _submitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    _HierarchyFormKind.state => 'Add state',
    _HierarchyFormKind.district => 'Add district',
    _HierarchyFormKind.cluster => 'Add cluster',
  };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _failure = null;
    });
    final SessionState session = ref.read(sessionProvider);
    final actorUserId = session.session?.user.userId ?? 'unknown';
    final actorRole = session.session?.user.role.wireName ?? 'UNKNOWN';
    final repo = ref.read(schoolHierarchyRepositoryProvider);
    final DateTime now = DateTime.now().toUtc();
    final String id = DateTime.now().microsecondsSinceEpoch.toString();

    late final Result<Object?> result;
    switch (widget.kind) {
      case _HierarchyFormKind.state:
        result = await repo.createState(
          StateEntity(
            stateId: 'st_$id',
            stateName: _nameController.text.trim(),
            stateCode: _codeController.text.trim(),
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
          actorUserId: actorUserId,
          actorRole: actorRole,
        );
      case _HierarchyFormKind.district:
        result = await repo.createDistrict(
          District(
            districtId: 'di_$id',
            districtName: _nameController.text.trim(),
            districtCode: _codeController.text.trim(),
            stateId: widget.parentStateId!,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
          actorUserId: actorUserId,
          actorRole: actorRole,
        );
      case _HierarchyFormKind.cluster:
        result = await repo.createCluster(
          Cluster(
            clusterId: 'cl_$id',
            clusterName: _nameController.text.trim(),
            clusterCode: _codeController.text.trim(),
            districtId: widget.parentDistrictId!,
            stateId: widget.parentStateId!,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
          actorUserId: actorUserId,
          actorRole: actorRole,
        );
    }

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
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(_title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (_failure != null) ...<Widget>[
                Text(
                  _failure!.userMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                enabled: !_submitting,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (String? v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeController,
                enabled: !_submitting,
                decoration: const InputDecoration(labelText: 'Code'),
                validator: (String? v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a code' : null,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Save'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
