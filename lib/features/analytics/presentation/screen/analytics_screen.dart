/// Analytics with a scope drill-down.
///
/// Design preview ahead of Phase 10. The breadcrumb is the point of the
/// screen: State → District → Cluster → School → Grade → Section → Student,
/// each step narrowing every figure below it and never reaching past the
/// caller's own scope.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/widgets/preview_kit.dart';

final class _Question {
  const _Question(this.number, this.correctPct, this.blankPct);
  final int number;
  final double correctPct;
  final double blankPct;
}

const List<_Question> _questions = <_Question>[
  _Question(1, 0.92, 0.01),
  _Question(2, 0.87, 0.02),
  _Question(3, 0.45, 0.09),
  _Question(4, 0.81, 0.03),
  _Question(5, 0.38, 0.22),
  _Question(6, 0.76, 0.04),
  _Question(7, 0.64, 0.06),
  _Question(8, 0.29, 0.31),
];

final class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;

    Color toneFor(double pct) => pct >= 0.6
        ? status.success
        : pct >= 0.4
        ? status.warning
        : status.danger;

    return PreviewScaffold(
      title: 'Analytics',
      phase: 'Phase 10',
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TextButton(onPressed: () {}, child: const Text('Demo State')),
            const Icon(Icons.chevron_right, size: 16),
            TextButton(onPressed: () {}, child: const Text('North District')),
            const Icon(Icons.chevron_right, size: 16),
            Text('Riverside Cluster', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        PreviewMetricRow(
          metrics: <PreviewMetric>[
            const PreviewMetric(label: 'Schools', value: '2'),
            const PreviewMetric(label: 'Students', value: '40'),
            PreviewMetric(
              label: 'Completion',
              value: '84%',
              tone: status.warning,
              caption: '27 of 32 expected',
            ),
            const PreviewMetric(label: 'Average', value: '34/50'),
          ],
        ),
        const SizedBox(height: 24),
        PreviewSection(
          title: 'OMR pipeline',
          subtitle: 'Where this cluster\'s sheets currently sit',
          child: PreviewListCard(
            children: previewDivided(<Widget>[
              _PipelineRow(
                label: 'Captured',
                value: 27,
                of: 32,
                color: status.success,
              ),
              _PipelineRow(
                label: 'Processed',
                value: 25,
                of: 32,
                color: status.success,
              ),
              _PipelineRow(
                label: 'Awaiting validation',
                value: 4,
                of: 32,
                color: status.warning,
              ),
              _PipelineRow(
                label: 'Scored',
                value: 21,
                of: 32,
                color: status.success,
              ),
              _PipelineRow(
                label: 'Sync failures',
                value: 1,
                of: 32,
                color: status.danger,
              ),
            ]),
          ),
        ),
        PreviewSection(
          title: 'Question performance',
          subtitle: 'Samagra 1 · Mathematics · % answering correctly',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: _questions
                    .map(
                      (_Question q) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 32,
                              child: Text(
                                'Q${q.number}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: PreviewBar(
                                fraction: q.correctPct,
                                color: toneFor(q.correctPct),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${(q.correctPct * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ),
        PreviewSection(
          title: 'Worth a teacher\'s attention',
          child: PreviewListCard(
            children: previewDivided(<Widget>[
              ListTile(
                leading: Icon(Icons.trending_down, color: status.danger),
                title: const Text('Q8 — 29% correct'),
                subtitle: const Text(
                  'Also the highest blank rate at 31%. Reads more like an '
                  'unfamiliar question than a hard one.',
                ),
              ),
              ListTile(
                leading: Icon(Icons.help_outline, color: status.warning),
                title: const Text('Q5 — 22% left blank'),
                subtitle: const Text(
                  'High blanks with moderate accuracy usually means the '
                  'question was not reached in time.',
                ),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Phase 10 computes these as server-side rollups on result '
              'publication, so a district dashboard never fans out over a '
              'hundred thousand answer documents from a phone. Every figure '
              'must reconcile against the raw results before this screen '
              'ships.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

final class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.label,
    required this.value,
    required this.of,
    required this.color,
  });

  final String label;
  final int value;
  final int of;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(child: PreviewBar(fraction: value / of, color: color)),
          const SizedBox(width: 12),
          Text(
            '$value',
            style: theme.textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
