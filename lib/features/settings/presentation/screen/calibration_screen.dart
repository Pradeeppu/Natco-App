/// Scanner calibration and accuracy measurement (Super Admin only).
///
/// Design preview ahead of Phase 6. Requirement §50 asks for this to be
/// admin-only and §49 forbids claiming an accuracy figure that has not been
/// measured — so the results panel here shows an empty state rather than a
/// plausible-looking number, which is what it will genuinely show until a
/// golden dataset has been run.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/core/widgets/preview_kit.dart';

final class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  double _fillThreshold = 0.55;
  double _ambiguityMargin = 0.12;
  double _blurFloor = 0.35;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;

    return PreviewScaffold(
      title: 'Scanner calibration',
      phase: 'Phase 6',
      children: <Widget>[
        Card(
          color: status.dangerContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.admin_panel_settings_outlined,
                    color: status.danger, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'These thresholds decide which sheets get read '
                    'automatically and which go to a human. Changing them '
                    'affects every scan from here on and is written to the '
                    'audit log with your name.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        PreviewSection(
          title: 'Thresholds',
          subtitle: 'Held in server config, not in the app binary',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  _Slider(
                    label: 'Fill threshold',
                    help: 'Darkness above which a bubble counts as marked',
                    value: _fillThreshold,
                    onChanged: (double v) =>
                        setState(() => _fillThreshold = v),
                  ),
                  _Slider(
                    label: 'Ambiguity margin',
                    help: 'If the top two options are closer than this, a '
                        'human decides',
                    value: _ambiguityMargin,
                    onChanged: (double v) =>
                        setState(() => _ambiguityMargin = v),
                  ),
                  _Slider(
                    label: 'Blur floor',
                    help: 'Sharpness below which the image is rejected',
                    value: _blurFloor,
                    onChanged: (double v) => setState(() => _blurFloor = v),
                  ),
                ],
              ),
            ),
          ),
        ),
        PreviewSection(
          title: 'Measure against a known set',
          subtitle: 'Upload sheets whose answers are already known',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload test sheets'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The harness compares every detected answer against the '
                    'ground truth and reports per-question accuracy, blank '
                    'and multiple-mark detection, and — the figure that '
                    'actually gates a release — the silent error rate: '
                    'answers the machine was confident about and got wrong.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        PreviewSection(
          title: 'Last measured accuracy',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: EmptyView(
                title: 'Nothing measured yet',
                message:
                    'No accuracy figure exists for this scanner, so none is '
                    'shown. It appears here after the first run against a '
                    'golden dataset.',
                icon: Icons.query_stats_outlined,
                action: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Run the harness'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String help;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
              Text(
                value.toStringAsFixed(2),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          Text(
            help,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
