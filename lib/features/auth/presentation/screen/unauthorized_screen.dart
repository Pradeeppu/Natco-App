/// Shown when a signed-in user reaches a route their role does not permit.
///
/// It names what was refused and offers a way back, rather than looking like a
/// crash. Requirement section 40: never a technical error, always a recovery
/// action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

final class UnauthorizedScreen extends ConsumerWidget {
  const UnauthorizedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final String roleName =
        session.session?.user.role.displayName ?? 'your role';

    return Scaffold(
      appBar: AppBar(title: const Text('Access restricted')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 20),
                Text(
                  'You do not have access to this screen',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'This area is not available to $roleName. If you need '
                  'access, ask your administrator to update your permissions.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => context.go(RoutePaths.dashboard),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Go to dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
