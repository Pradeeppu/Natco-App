/// Report generation and export.
///
/// Design preview ahead of Phase 11. CSV first; the architecture leaves room
/// for PDF and Excel without rewriting the exporters (requirement §32).
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/widgets/preview_kit.dart';
import 'package:natco_app/core/widgets/status_chip.dart';

final class _Report {
  const _Report(this.name, this.description, this.icon);
  final String name;
  final String description;
  final IconData icon;
}

const List<_Report> _reports = <_Report>[
  _Report('Student result', 'One row per student, with question-level marks',
      Icons.person_outline),
  _Report('School summary', 'Participation, average, spread, per grade',
      Icons.school_outlined),
  _Report('Cluster summary', 'School-by-school comparison within a cluster',
      Icons.hub_outlined),
  _Report('District summary', 'Cluster-by-cluster comparison',
      Icons.location_city_outlined),
  _Report('Assessment summary', 'One assessment across every school assigned',
      Icons.assignment_outlined),
  _Report('Question analysis', 'Correct, incorrect, blank and multiple per Q',
      Icons.query_stats_outlined),
  _Report('OMR processing', 'Captured, processed, pending, by school and day',
      Icons.document_scanner_outlined),
  _Report('Validation', 'Every human decision, who made it and why',
      Icons.how_to_reg_outlined),
  _Report('Sync failures', 'What has not reached the server, and why',
      Icons.cloud_off_outlined),
];

final class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PreviewScaffold(
      title: 'Reports',
      phase: 'Phase 11',
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Export covers', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(label: Text('Riverside Cluster')),
                    Chip(label: Text('Samagra 1')),
                    Chip(label: Text('2026-27')),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Scoped to what your account can already see — an export '
                  'can never widen your reach.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        PreviewSection(
          title: 'Available reports',
          subtitle: 'CSV',
          child: PreviewListCard(
            children: previewDivided(
              _reports
                  .map(
                    (_Report r) => ListTile(
                      leading: Icon(r.icon),
                      title: Text(r.name),
                      subtitle: Text(r.description),
                      trailing: IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Export ${r.name} as CSV',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        PreviewSection(
          title: 'Recent exports',
          child: PreviewListCard(
            children: previewDivided(<Widget>[
              const ListTile(
                title: Text('question_analysis_20260908.csv'),
                subtitle: Text('Today 15:12 · Riverside Cluster · 50 rows'),
                trailing: StatusChip(
                  label: 'Ready',
                  tone: StatusTone.success,
                ),
              ),
              const ListTile(
                title: Text('school_summary_20260907.csv'),
                subtitle: Text('Yesterday 09:40 · Riverside Cluster · 2 rows'),
                trailing: StatusChip(
                  label: 'Ready',
                  tone: StatusTone.success,
                ),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Every export is written to the audit log with who ran it and '
              'what it covered, and no student name appears in any filename — '
              'the identity stays in the file, behind the access check, not '
              'in something that ends up in a downloads folder.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}
