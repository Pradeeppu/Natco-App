/// The scan result for one sheet, straight after processing.
///
/// Design preview ahead of Phase 6. The score shown here is a *preview* — it
/// is what the machine reading alone produces, and the screen refuses to call
/// it final while any answer still needs a human (requirement §39).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/widgets/preview_kit.dart';
import 'package:natco_app/core/widgets/status_chip.dart';

final class OmrReviewScreen extends StatelessWidget {
  const OmrReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;

    const int total = 50;
    const int high = 46;
    const int medium = 2;
    const int needsReview = 1;
    const int blank = 1;

    return PreviewScaffold(
      title: 'Scan result',
      phase: 'Phase 6',
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('OMR 0001827',
                          style: theme.textTheme.titleMedium),
                    ),
                    const StatusChip(
                      label: 'Needs validation',
                      tone: StatusTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Ananya Verma · Grade 5-A · Samagra 1 · Mathematics',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        PreviewSection(
          title: 'What the machine read',
          subtitle: '$total questions detected',
          child: PreviewListCard(
            children: previewDivided(<Widget>[
              _DetectionRow(
                label: 'High confidence',
                count: high,
                total: total,
                color: status.success,
                note: 'Scored automatically',
              ),
              _DetectionRow(
                label: 'Medium confidence',
                count: medium,
                total: total,
                color: status.warning,
                note: 'Flagged for a second look',
              ),
              _DetectionRow(
                label: 'Needs review',
                count: needsReview,
                total: total,
                color: status.danger,
                note: 'Two bubbles filled on Q17',
              ),
              _DetectionRow(
                label: 'Blank',
                count: blank,
                total: total,
                color: theme.colorScheme.onSurfaceVariant,
                note: 'Recorded as blank, not as wrong',
              ),
            ]),
          ),
        ),
        PreviewSection(
          title: 'Score preview',
          subtitle: 'Machine reading only — not a final result',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text('42', style: theme.textTheme.displaySmall),
                      Text(
                        ' / 50',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: status.warningContainer,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.lock_outline,
                            size: 18, color: status.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This score cannot be published while 3 answers '
                            'still need a human decision. Validation comes '
                            'first, then scoring.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: status.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => context.push(
            RoutePaths.of(RoutePaths.omrValidationDetail, <String, String>{
              'omrId': '0001827',
            }),
          ),
          icon: const Icon(Icons.rule),
          label: const Text('Review 3 answers'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.image_outlined),
          label: const Text('View original sheet'),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Phase 6 runs the eleven pipeline stages in a worker isolate so '
              'the UI never freezes, and stores the per-option darkness '
              'scores behind each of these numbers as evidence. Nothing here '
              'is a measured accuracy figure — that arrives with the golden '
              'dataset harness in the same phase.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

final class _DetectionRow extends StatelessWidget {
  const _DetectionRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
    required this.note,
  });

  final String label;
  final int count;
  final int total;
  final Color color;
  final String note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(
                '$count',
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PreviewBar(fraction: count / total, color: color),
          const SizedBox(height: 6),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
