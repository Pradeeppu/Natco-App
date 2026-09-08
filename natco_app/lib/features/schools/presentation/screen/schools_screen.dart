/// Browses the State / District / Cluster / School hierarchy, restricted to
/// the signed-in user's scope, with search and pagination
/// (requirement sections 10 and 42).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';
import 'package:natco_app/features/schools/domain/entity/hierarchy_level.dart';
import 'package:natco_app/features/schools/presentation/controller/schools_browser_controller.dart';
import 'package:natco_app/features/schools/presentation/controller/schools_browser_state.dart';
import 'package:natco_app/features/schools/presentation/widget/create_hierarchy_node_dialog.dart';
import 'package:natco_app/features/schools/presentation/widget/school_form_dialog.dart';

final class SchoolsScreen extends ConsumerStatefulWidget {
  const SchoolsScreen({super.key});

  @override
  ConsumerState<SchoolsScreen> createState() => _SchoolsScreenState();
}

class _SchoolsScreenState extends ConsumerState<SchoolsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(schoolsBrowserProvider.notifier).loadMore();
    }
  }

  String _titleFor(BrowseLevel level) => switch (level) {
    BrowseLevel.states => 'States',
    BrowseLevel.districts => 'Districts',
    BrowseLevel.clusters => 'Clusters',
    BrowseLevel.schools => 'Schools',
  };

  /// The permission that gates creating a new node at the current level, or
  /// `null` when nothing can be created here (the flat schools search mode
  /// for a narrowly-scoped user has no parent to attach a new school to).
  Permission? _createPermissionFor(SchoolsBrowserState state) =>
      switch (state.level) {
        BrowseLevel.states => Permission.manageStates,
        BrowseLevel.districts =>
          state.parentId == null ? null : Permission.manageDistricts,
        BrowseLevel.clusters =>
          state.parentId == null ? null : Permission.manageClusters,
        BrowseLevel.schools =>
          state.parentId == null ? null : Permission.manageSchools,
      };

  Future<void> _createNode(SchoolsBrowserState state, BrowseLevel level) async {
    final HierarchyLevel domainLevel = switch (level) {
      BrowseLevel.states => HierarchyLevel.state,
      BrowseLevel.districts => HierarchyLevel.district,
      BrowseLevel.clusters => HierarchyLevel.cluster,
      BrowseLevel.schools => HierarchyLevel.school,
    };
    await showCreateHierarchyNodeDialog(
      context: context,
      level: domainLevel,
      onSubmit: (HierarchyNodeDraft draft) async {
        final repository = ref.read(schoolsRepositoryProvider);
        final result = switch (level) {
          BrowseLevel.states => await repository.createState(
            name: draft.name,
            code: draft.code,
          ),
          BrowseLevel.districts => await repository.createDistrict(
            name: draft.name,
            code: draft.code,
            stateId: state.parentId!,
          ),
          BrowseLevel.clusters => await repository.createCluster(
            name: draft.name,
            code: draft.code,
            districtId: state.parentId!,
          ),
          BrowseLevel.schools => throw StateError('use _createSchool'),
        };
        return result.failureOrNull;
      },
    );
    if (mounted) {
      await ref.read(schoolsBrowserProvider.notifier).refresh();
    }
  }

  Future<void> _createSchool(String clusterId) async {
    await showSchoolFormDialog(
      context: context,
      onSubmit: (SchoolDraft draft) async {
        final result = await ref
            .read(schoolsRepositoryProvider)
            .createSchool(
              schoolName: draft.schoolName,
              schoolCode: draft.schoolCode,
              clusterId: clusterId,
              grades: draft.grades,
              mediumsOfInstruction: draft.mediumsOfInstruction,
              address: draft.address,
              pincode: draft.pincode,
            );
        return result.failureOrNull;
      },
    );
    if (mounted) {
      await ref.read(schoolsBrowserProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SchoolsBrowserState state = ref.watch(schoolsBrowserProvider);
    final Authorization authorization = ref
        .watch(sessionProvider)
        .authorization;
    final Permission? createPermission = _createPermissionFor(state);
    final bool canCreate =
        createPermission != null && authorization.can(createPermission);

    return Scaffold(
      appBar: AppBar(title: Text(_titleFor(state.level))),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (state.breadcrumbs.isNotEmpty) _BreadcrumbBar(state: state),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search ${_titleFor(state.level).toLowerCase()}',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            ref
                                .read(schoolsBrowserProvider.notifier)
                                .search('');
                          },
                        ),
                ),
                onChanged: (String value) => setState(() {}),
                onSubmitted: (String value) =>
                    ref.read(schoolsBrowserProvider.notifier).search(value),
              ),
            ),
            Expanded(child: _buildBody(state)),
          ],
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: state.level == BrowseLevel.schools
                  ? () => _createSchool(state.parentId!)
                  : () => _createNode(state, state.level),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
    );
  }

  Widget _buildBody(SchoolsBrowserState state) {
    if (state.isLoading && state.rows.isEmpty) {
      return const LoadingView();
    }
    if (state.failure != null && state.rows.isEmpty) {
      return FailureView(
        failure: state.failure!,
        onRetry: () => ref.read(schoolsBrowserProvider.notifier).refresh(),
      );
    }
    if (state.rows.isEmpty) {
      return EmptyView(
        title: 'Nothing here yet',
        message: state.query.isEmpty
            ? 'No ${_titleFor(state.level).toLowerCase()} found in your assigned area.'
            : 'No results for "${state.query}".',
        icon: Icons.folder_open_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(schoolsBrowserProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: state.rows.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          if (index >= state.rows.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final HierarchyRow row = state.rows[index];
          return switch (row) {
            NodeRow() => ListTile(
              leading: Icon(_iconFor(state.level)),
              title: Text(row.title),
              subtitle: Text(row.node.code),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  ref.read(schoolsBrowserProvider.notifier).drillInto(row),
            ),
            SchoolRow() => ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(row.title),
              subtitle: Text(
                <String>[
                  row.school.schoolCode,
                  if (row.school.address != null) row.school.address!,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(
                RoutePaths.of(RoutePaths.schoolDetail, <String, String>{
                  'schoolId': row.school.schoolId,
                }),
              ),
            ),
          };
        },
      ),
    );
  }

  IconData _iconFor(BrowseLevel level) => switch (level) {
    BrowseLevel.states => Icons.map_outlined,
    BrowseLevel.districts => Icons.location_city_outlined,
    BrowseLevel.clusters => Icons.hub_outlined,
    BrowseLevel.schools => Icons.school_outlined,
  };
}

final class _BreadcrumbBar extends ConsumerWidget {
  const _BreadcrumbBar({required this.state});

  final SchoolsBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            InkWell(
              onTap: () => ref.read(schoolsBrowserProvider.notifier).goToRoot(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.home_outlined, size: 18),
              ),
            ),
            for (int i = 0; i < state.breadcrumbs.length; i++) ...<Widget>[
              const Icon(Icons.chevron_right, size: 16),
              InkWell(
                onTap: () =>
                    ref.read(schoolsBrowserProvider.notifier).goToBreadcrumb(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    state.breadcrumbs[i].label,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
