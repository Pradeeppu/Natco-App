/// A screen for a feature whose implementation belongs to a later phase.
///
/// This is not a `TODO` hidden in a widget. Requirement section 65 asks that
/// deferred work be documented clearly, and requirement section 58 asks that
/// the app be built phase by phase. A route that resolves, states which phase
/// owns it, and shows what the signed-in user's scope would be is more honest
/// than a dead link — and it lets the routing and permission model be
/// exercised end to end now, which is the whole point of phase 1.
///
/// Each of these is replaced by the real screen in the phase named on it; the
/// mapping is in docs/08-mvp-implementation-plan.md.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/status_chip.dart';

final class FeaturePreviewScreen extends StatelessWidget {
  const FeaturePreviewScreen({
    required this.title,
    required this.phase,
    required this.summary,
    this.capabilities = const <String>[],
    this.icon = Icons.dashboard_customize_outlined,
    super.key,
  });

  /// Feature name, matching the navigation destination.
  final String title;

  /// The implementation phase, e.g. `'Phase 2 — Master Data'`.
  final String phase;

  /// One or two sentences on what this screen will do.
  final String summary;

  /// The specific behaviours the phase delivers here.
  final List<String> capabilities;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 28, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: theme.textTheme.headlineSmall),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StatusChip(
                label: phase,
                tone: StatusTone.pending,
                icon: Icons.construction_outlined,
              ),
              const SizedBox(height: 20),
              Text(summary, style: theme.textTheme.bodyLarge),
              if (capabilities.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                Text('This phase delivers', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...capabilities.map(
                  (String capability) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            capability,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You reached this screen, so your role holds the '
                          'permission it requires and the route guard allowed '
                          'it. Server-side rules enforce the same decision '
                          'independently.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
