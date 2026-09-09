/// Users: the people who work in the caller's own area.
///
/// A Supervisor uses this to onboard the PST Teachers in their clusters; a
/// Super Admin uses it for everyone. The list is already scope-filtered by the
/// repository, so this screen shows what it is given.
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
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/users/domain/service/user_provisioning_policy.dart';
import 'package:natco_app/features/users/presentation/controller/user_list_controller.dart';

final class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(userListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final List<UserRole> assignable = UserProvisioningPolicy.assignableRolesFor(
      session.authorization.user,
    );
    final AsyncValue<PagedListState<AppUser>> value = ref.watch(
      userListControllerProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      // Built from the policy rather than from `Permission.manageUsers` alone:
      // a role that can manage users but has nothing it may assign would
      // otherwise get a button leading to a form that can only be refused.
      floatingActionButton: assignable.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(RoutePaths.userNew),
              icon: const Icon(Icons.person_add_alt_outlined),
              label: Text(
                assignable.length == 1
                    ? 'Add ${assignable.single.displayName}'
                    : 'Add user',
              ),
            ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search by name or email',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (String q) =>
                    ref.read(userListControllerProvider.notifier).setQuery(q),
              ),
            ),
            Expanded(
              child: value.when(
                loading: () => const LoadingView(),
                error: (Object error, StackTrace _) => FailureView(
                  failure: asFailure(error),
                  onRetry: () =>
                      ref.read(userListControllerProvider.notifier).refresh(),
                ),
                data: (PagedListState<AppUser> state) {
                  final Failure? failure = state.failure;
                  if (failure != null) {
                    return FailureView(
                      failure: failure,
                      onRetry: () => ref
                          .read(userListControllerProvider.notifier)
                          .refresh(),
                    );
                  }
                  if (state.items.isEmpty) {
                    return const EmptyView(
                      title: 'No users found',
                      message:
                          'Nobody is registered in your area yet. Add the '
                          'teachers who will run assessments.',
                      icon: Icons.badge_outlined,
                    );
                  }
                  return ListView.separated(
                    controller: _scrollController,
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        );
                      }
                      final AppUser user = state.items[index];
                      return ListTile(
                        leading: Icon(
                          user.isActive
                              ? Icons.person_outline
                              : Icons.person_off_outlined,
                        ),
                        title: Text(user.displayName),
                        subtitle: Text(
                          user.isActive
                              ? user.role.displayName
                              : '${user.role.displayName} - deactivated',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          RoutePaths.of(RoutePaths.userDetail, <String, String>{
                            'userId': user.userId,
                          }),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
