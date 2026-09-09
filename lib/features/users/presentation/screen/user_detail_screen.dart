/// One user account: what they can reach, and whether they can sign in.
///
/// Deactivation rather than deletion, because a deleted user would orphan
/// every audit entry, captured sheet and score correction naming them, and the
/// audit trail has to stay answerable (requirement §26).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/users/domain/service/user_provisioning_policy.dart';
import 'package:natco_app/features/users/presentation/controller/user_list_controller.dart';

final class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  bool _working = false;

  Future<void> _setActive(AppUser user, bool isActive) async {
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }
    setState(() => _working = true);
    final Result<AppUser> result = await ref
        .read(userRepositoryProvider)
        .setUserActive(user.userId, isActive: isActive, actor: actor);
    if (!mounted) {
      return;
    }
    setState(() => _working = false);

    result.fold(
      onSuccess: (_) {
        ref.invalidate(userProvider(widget.userId));
        ref.read(userListControllerProvider.notifier).refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isActive
                  ? '${user.displayName} can sign in again.'
                  : '${user.displayName} can no longer sign in.',
            ),
          ),
        );
      },
      onFailure: (Failure failure) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.userMessage)));
      },
    );
  }

  Future<void> _confirmDeactivate(AppUser user) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Deactivate this account?'),
        content: Text(
          '${user.displayName} will not be able to sign in. Everything they '
          'have already captured is kept, and their name stays on it.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _setActive(user, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppUser> value = ref.watch(userProvider(widget.userId));
    final AppUser? actor = ref.watch(sessionProvider).authorization.user;

    return Scaffold(
      appBar: AppBar(title: const Text('User')),
      body: SafeArea(
        child: value.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () => ref.invalidate(userProvider(widget.userId)),
          ),
          data: (AppUser user) {
            // The same rule the repository enforces: you may only act on an
            // account you could have created.
            final bool mayManage =
                UserProvisioningPolicy.checkRoleGrant(
                  actor: actor,
                  role: user.role,
                ) ==
                null;
            final bool isSelf = actor?.userId == user.userId;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                if (!user.isActive) ...<Widget>[
                  const InfoBanner(
                    message: 'This account is deactivated and cannot sign in.',
                    icon: Icons.person_off_outlined,
                    isWarning: true,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  user.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Divider(height: 32),
                _Row(label: 'Role', value: user.role.displayName),
                if (user.phone != null)
                  _Row(label: 'Phone', value: user.phone!),
                _Row(label: 'Access', value: _scopeSummary(user.scope)),
                if (user.scope.gradeSections.isNotEmpty)
                  _Row(
                    label: 'Classes',
                    value: (user.scope.gradeSections.toList()..sort())
                        .map((GradeSection gs) => gs.displayName)
                        .join(', '),
                  ),
                _Row(
                  label: 'Last signed in',
                  value: user.lastLoginAt == null
                      ? 'Never'
                      : user.lastLoginAt!.toLocal().toString().split('.').first,
                ),
                if (mayManage && !isSelf) ...<Widget>[
                  const SizedBox(height: 32),
                  if (user.isActive)
                    OutlinedButton.icon(
                      onPressed:
                          _working ? null : () => _confirmDeactivate(user),
                      icon: const Icon(Icons.person_off_outlined),
                      label: const Text('Deactivate account'),
                    )
                  else
                    FilledButton.icon(
                      onPressed:
                          _working ? null : () => _setActive(user, true),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Reactivate account'),
                    ),
                ],
                if (isSelf) ...<Widget>[
                  const SizedBox(height: 32),
                  const InfoBanner(
                    message:
                        'This is your own account. Someone else with user '
                        'management has to change it.',
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static String _scopeSummary(AccessScope scope) => switch (scope.level) {
    ScopeLevel.global => 'The entire programme',
    ScopeLevel.state => '${scope.stateIds.length} state(s)',
    ScopeLevel.district => '${scope.districtIds.length} district(s)',
    ScopeLevel.cluster => '${scope.clusterIds.length} cluster(s)',
    ScopeLevel.school => '${scope.schoolIds.length} school(s)',
  };
}

final class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
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
