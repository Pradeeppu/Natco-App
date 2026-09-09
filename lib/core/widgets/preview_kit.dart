/// Shared building blocks for the phase-3-to-11 screens while they are still
/// design previews.
///
/// These screens exist ahead of their phases so the team can review the flows
/// before the engines behind them are built. That creates one hazard worth
/// naming: Critical Rule 14 says this product shows no number it has not
/// measured, and a mocked "96% confidence" on a polished screen is exactly how
/// an invented figure gets quoted back as fact.
///
/// [PreviewScaffold] therefore puts an unmissable band at the top of every one
/// of these screens. Nothing here is wired to a repository; every figure is
/// illustrative. When a phase lands, its screen drops the scaffold and reads
/// real data — the banner disappearing is the signal that the numbers became
/// real.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/app/theme.dart';

/// Wraps a preview screen with its app bar and the sample-data band.
final class PreviewScaffold extends StatelessWidget {
  const PreviewScaffold({
    required this.title,
    required this.phase,
    required this.children,
    this.actions = const <Widget>[],
    this.floatingActionButton,
    this.leading,
    super.key,
  });

  final String title;

  /// The phase that replaces this preview with the real screen.
  final String phase;

  final List<Widget> children;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions, leading: leading),
    floatingActionButton: floatingActionButton,
    body: SafeArea(
      child: Column(
        children: <Widget>[
          PreviewBanner(phase: phase),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The sample-data band. Deliberately plain and full-width rather than a
/// dismissible chip: it has to survive a screenshot taken out of context.
final class PreviewBanner extends StatelessWidget {
  const PreviewBanner({required this.phase, super.key});

  final String phase;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    return Container(
      width: double.infinity,
      color: status.warningContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.science_outlined, size: 18, color: status.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Design preview — every figure below is made up. $phase builds '
              'this screen against real data.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: status.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled block with an optional trailing action.
final class PreviewSection extends StatelessWidget {
  const PreviewSection({
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A figure with its label. Used only inside [PreviewScaffold], so the
/// sample-data band is always on screen with it.
final class PreviewMetric extends StatelessWidget {
  const PreviewMetric({
    required this.label,
    required this.value,
    this.tone,
    this.caption,
    super.key,
  });

  final String label;
  final String value;
  final Color? tone;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: tone ?? theme.colorScheme.onSurface,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (caption != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// A row of metrics that wraps rather than overflowing on a 5-inch screen.
final class PreviewMetricRow extends StatelessWidget {
  const PreviewMetricRow({required this.metrics, super.key});

  final List<PreviewMetric> metrics;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(spacing: 32, runSpacing: 20, children: metrics),
    ),
  );
}

/// A label/value pair for detail screens.
final class PreviewField extends StatelessWidget {
  const PreviewField({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal proportion bar. Used for confidence and for per-question
/// correctness, where a number alone is hard to scan down a list.
final class PreviewBar extends StatelessWidget {
  const PreviewBar({
    required this.fraction,
    required this.color,
    this.height = 8,
    super.key,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(height)),
      child: LinearProgressIndicator(
        value: fraction.clamp(0, 1),
        minHeight: height,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// A tappable row inside a card list.
final class PreviewListCard extends StatelessWidget {
  const PreviewListCard({required this.children, this.padding, super.key});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(children: children),
    ),
  );
}

/// Separates rows inside a [PreviewListCard] without a trailing divider.
List<Widget> previewDivided(List<Widget> rows) {
  final List<Widget> out = <Widget>[];
  for (int i = 0; i < rows.length; i++) {
    out.add(rows[i]);
    if (i != rows.length - 1) {
      out.add(const Divider(height: 1, indent: 16, endIndent: 16));
    }
  }
  return out;
}
