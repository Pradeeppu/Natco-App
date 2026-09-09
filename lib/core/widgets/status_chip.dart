/// A status pill.
///
/// Status is always colour **and** icon **and** text. Colour alone fails for
/// the roughly 1-in-12 men with a colour-vision deficiency, and fails again in
/// direct sunlight on a cheap screen (requirement section 56).
library;

import 'package:flutter/material.dart';
import 'package:natco_app/app/theme.dart';

/// The semantic families a status can belong to.
enum StatusTone { success, warning, danger, pending, neutral }

final class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });

  final String label;
  final StatusTone tone;

  /// Overrides the tone's default icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final (
      Color background,
      Color foreground,
      IconData defaultIcon,
    ) = switch (tone) {
      StatusTone.success => (
        status.successContainer,
        status.success,
        Icons.check_circle_outline,
      ),
      StatusTone.warning => (
        status.warningContainer,
        status.warning,
        Icons.warning_amber_outlined,
      ),
      StatusTone.danger => (
        status.dangerContainer,
        status.danger,
        Icons.error_outline,
      ),
      StatusTone.pending => (
        status.pendingContainer,
        status.pending,
        Icons.schedule,
      ),
      StatusTone.neutral => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
        Icons.info_outline,
      ),
    };

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon ?? defaultIcon, size: 16, color: foreground),
            const SizedBox(width: 6),
            // Flexible, not a bare Text: a long label ("Phase 9 —
            // Synchronization") inside a Wrap on a 5-inch screen gets less
            // width than its natural size, and a chip that overflows hides
            // the status it exists to show.
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
