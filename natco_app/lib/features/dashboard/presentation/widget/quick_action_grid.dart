/// Permission-filtered quick actions.
///
/// The dashboard's job (requirement section 62) is status, next action,
/// exceptions, progress — in that order. This widget owns "next action", and
/// it renders only the actions the signed-in user actually holds, so a teacher
/// is not shown a tile that will bounce them to the unauthorized screen.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';

/// One action tile.
final class QuickAction {
  const QuickAction({
    required this.label,
    required this.description,
    required this.icon,
    required this.route,
    required this.permission,
    this.isPrimary = false,
  });

  final String label;
  final String description;
  final IconData icon;
  final String route;

  /// The permission required to reach [route]. The same permission the route
  /// guard checks, so the tile and the guard cannot disagree.
  final Permission permission;

  /// Primary actions get filled emphasis; everything else is outlined
  /// (requirement section 62).
  final bool isPrimary;
}

final class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({
    required this.actions,
    required this.authorization,
    required this.onSelected,
    super.key,
  });

  final List<QuickAction> actions;
  final Authorization authorization;
  final ValueChanged<QuickAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<QuickAction> permitted = actions
        .where((QuickAction a) => authorization.can(a.permission))
        .toList(growable: false);
    if (permitted.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: permitted
          .map(
            (QuickAction action) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ActionTile(
                action: action,
                onTap: () => onSelected(action),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});

  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = action.isPrimary
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    final Color foreground = action.isPrimary
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Material(
      color: background,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: Container(
          // Comfortably above the 48dp minimum: this is the tile a teacher
          // taps while holding a stack of sheets.
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(
              color: action.isPrimary
                  ? Colors.transparent
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(action.icon, size: 26, color: foreground),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      action.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
