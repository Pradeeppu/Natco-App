/// Scanner calibration and single-sheet accuracy check (Super Admin only).
///
/// The threshold sliders below build a real [ScannerThresholds] draft, and
/// "Test one sheet" actually decodes a picked image and runs [OmrProcessor]
/// against it with that draft — nothing on this screen is sample data.
///
/// What genuinely isn't built yet is the golden-dataset harness
/// (`tool/omr_eval.dart`) and a labelled dataset to run it against, so the
/// aggregate accuracy section below stays an honest empty state rather than
/// a number — Critical Rule 14 forbids claiming a figure nothing measured,
/// and a single sheet is not a golden dataset. `flutter analyze`/`flutter
/// test` are the only claims this screen is allowed to make about itself.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processor.dart';

/// Ground-truth tokens this screen accepts, typed comma- or newline-separated
/// — one per question, in order. `?` marks a question the admin doesn't know
/// the truth for, so it is shown but never counted for or against the match
/// rate.
const Set<String> _kGroundTruthTokens = <String>{
  'A',
  'B',
  'C',
  'D',
  'BLANK',
  'MULTIPLE',
  '?',
};

final class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const BubbleThresholds _bubbleDefaults = BubbleThresholds();
  static const ImageQualityThresholds _imageQualityDefaults =
      ImageQualityThresholds();

  double _fillThreshold = _bubbleDefaults.filledThreshold;
  double _ambiguityMargin = _bubbleDefaults.ambiguousMargin;
  double _blurFloor = _imageQualityDefaults.minBlurScore;

  final TextEditingController _groundTruthController =
      TextEditingController();

  Uint8List? _imageBytes;
  String? _imageName;
  bool _running = false;
  String? _error;
  _SheetTestOutcome? _outcome;

  ScannerThresholds get _draftThresholds => ScannerThresholds(
    bubbles: BubbleThresholds(
      filledThreshold: _fillThreshold,
      ambiguousMargin: _ambiguityMargin,
    ),
    imageQuality: ImageQualityThresholds(minBlurScore: _blurFloor),
  );

  @override
  void dispose() {
    _groundTruthController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
    } catch (_) {
      setState(
        () => _error = 'Could not open the gallery on this device.',
      );
      return;
    }
    if (file == null || !mounted) {
      return; // Cancelled — not an error.
    }
    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _imageBytes = bytes;
      _imageName = file!.name;
      _outcome = null;
      _error = null;
    });
  }

  List<String>? _parseGroundTruth(String raw) {
    final List<String> tokens = raw
        .split(RegExp(r'[,\n]+'))
        .map((String t) => t.trim().toUpperCase())
        .where((String t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty ||
        tokens.any((String t) => !_kGroundTruthTokens.contains(t))) {
      return null;
    }
    return tokens;
  }

  Future<void> _run() async {
    final Uint8List? bytes = _imageBytes;
    if (bytes == null) {
      return;
    }
    final List<String>? groundTruth = _parseGroundTruth(
      _groundTruthController.text,
    );
    if (groundTruth == null) {
      setState(
        () => _error =
            'Enter one ground-truth answer per question, separated by '
            'commas: A, B, C, D, BLANK, MULTIPLE, or ? if unknown.',
      );
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _outcome = null;
    });

    final OmrProcessingResult result = await compute(
      _runCalibrationProcessor,
      _CalibrationProcessorPayload(
        imageBytes: bytes,
        thresholds: _draftThresholds,
        questionCount: groundTruth.length,
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _outcome = _SheetTestOutcome(result: result, groundTruth: groundTruth);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Scanner calibration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: <Widget>[
            const InfoBanner(
              isWarning: true,
              icon: Icons.admin_panel_settings_outlined,
              message:
                  'These thresholds decide which sheets get read '
                  'automatically and which go to a human. They are used '
                  'below to test one sheet; nothing here is saved yet — '
                  'there is no threshold-publishing backend in this build.',
            ),
            const SizedBox(height: 24),
            const _SectionTitle(
              title: 'Thresholds',
              subtitle: 'Applied to the test below, not yet persisted',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    _Slider(
                      label: 'Fill threshold',
                      help:
                          'Darkness above which a bubble counts as marked',
                      value: _fillThreshold,
                      onChanged: (double v) =>
                          setState(() => _fillThreshold = v),
                    ),
                    _Slider(
                      label: 'Ambiguity margin',
                      help:
                          'If the top two options are closer than this, a '
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
            const SizedBox(height: 24),
            const _SectionTitle(
              title: 'Test one sheet',
              subtitle:
                  'Runs the real scanner against one image with thresholds '
                  'from above',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _running ? null : _pickImage,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _imageName == null
                            ? 'Upload test OMR'
                            : 'Change sheet ($_imageName)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _groundTruthController,
                      enabled: !_running,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Ground truth, one per question',
                        hintText: 'A, B, C, BLANK, D, MULTIPLE, ...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: status.danger,
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: _imageBytes == null || _running
                          ? null
                          : _run,
                      icon: _running
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.play_arrow_outlined),
                      label: Text(_running ? 'Running...' : 'Run'),
                    ),
                  ],
                ),
              ),
            ),
            if (_outcome != null) ...<Widget>[
              const SizedBox(height: 24),
              const _SectionTitle(title: 'Result — this sheet only'),
              _OutcomeCard(outcome: _outcome!),
            ],
            const SizedBox(height: 24),
            const _SectionTitle(title: 'Measured accuracy across a dataset'),
            const Card(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: EmptyView(
                  title: 'Nothing measured yet',
                  message:
                      'No golden-dataset harness run has been recorded, so '
                      'no accuracy figure is shown for the scanner as a '
                      'whole. A single sheet above proves the pipeline runs '
                      'end to end; it is not a substitute for one.',
                  icon: Icons.query_stats_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
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

final class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome});

  final _SheetTestOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final OmrProcessingResult result = outcome.result;

    if (!result.sheetAligned) {
      return Card(
        color: status.dangerContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, color: status.danger, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result.failureReason ?? 'The sheet could not be aligned.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: status.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final List<_ComparisonRow> rows = outcome.rows;
    final int comparable = outcome.comparableCount;
    final int matched = outcome.matchCount;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    comparable == 0
                        ? 'No comparable questions (every answer was marked '
                              '"?")'
                        : '$matched of $comparable questions matched on '
                              'this sheet',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (!result.omrIdReadable)
                  Tooltip(
                    message: 'The omrId grid was not read as high-confidence',
                    child: Icon(
                      Icons.badge_outlined,
                      size: 18,
                      color: status.warning,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i != 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _ComparisonTile(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

final class _ComparisonTile extends StatelessWidget {
  const _ComparisonTile({required this.row});

  final _ComparisonRow row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final OmrQuestionReading? reading = row.reading;

    final (IconData icon, Color color) = switch (row.isMatch) {
      true => (Icons.check_circle_outline, status.success),
      false => (Icons.cancel_outlined, status.danger),
      null => (Icons.help_outline, theme.colorScheme.onSurfaceVariant),
    };

    final String machineLabel = reading == null
        ? 'not read'
        : switch (reading.machineStatus) {
            DetectionStatus.blank => 'BLANK',
            DetectionStatus.multipleMark => 'MULTIPLE',
            DetectionStatus.unreadable => 'unreadable',
            _ => reading.machineAnswer ?? '—',
          };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text('Q${row.questionNumber}'),
      subtitle: Text(
        'Truth: ${row.truth}  ·  Machine: $machineLabel'
        '${reading != null ? '  ·  ${reading.machineStatus.wireName}' : ''}',
      ),
      trailing: reading == null
          ? null
          : Text(
              '${(reading.machineConfidence * 100).round()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
    );
  }
}

final class _ComparisonRow {
  const _ComparisonRow({
    required this.questionNumber,
    required this.truth,
    required this.reading,
    required this.isMatch,
  });

  final int questionNumber;
  final String truth;
  final OmrQuestionReading? reading;

  /// `null` when [truth] is `?` (unknown) or the question wasn't read at all
  /// — neither counts for or against the match rate.
  final bool? isMatch;
}

final class _SheetTestOutcome {
  const _SheetTestOutcome({required this.result, required this.groundTruth});

  final OmrProcessingResult result;
  final List<String> groundTruth;

  List<_ComparisonRow> get rows {
    final Map<int, OmrQuestionReading> byQuestion = <int, OmrQuestionReading>{
      for (final OmrQuestionReading q in result.questions) q.questionNumber: q,
    };
    return List<_ComparisonRow>.generate(groundTruth.length, (int i) {
      final int questionNumber = i + 1;
      final String truth = groundTruth[i];
      final OmrQuestionReading? reading = byQuestion[questionNumber];
      final bool? isMatch = (truth == '?' || reading == null)
          ? null
          : _matches(truth, reading);
      return _ComparisonRow(
        questionNumber: questionNumber,
        truth: truth,
        reading: reading,
        isMatch: isMatch,
      );
    });
  }

  int get comparableCount =>
      rows.where((_ComparisonRow r) => r.isMatch != null).length;

  int get matchCount =>
      rows.where((_ComparisonRow r) => r.isMatch == true).length;

  static bool _matches(String truth, OmrQuestionReading reading) =>
      switch (truth) {
        'BLANK' => reading.machineStatus == DetectionStatus.blank,
        'MULTIPLE' => reading.machineStatus == DetectionStatus.multipleMark,
        _ => reading.machineAnswer == truth,
      };
}

final class _CalibrationProcessorPayload {
  const _CalibrationProcessorPayload({
    required this.imageBytes,
    required this.thresholds,
    required this.questionCount,
  });

  final Uint8List imageBytes;
  final ScannerThresholds thresholds;
  final int questionCount;
}

OmrProcessingResult _runCalibrationProcessor(
  _CalibrationProcessorPayload payload,
) {
  final img.Image? decoded = img.decodeImage(payload.imageBytes);
  if (decoded == null) {
    return const OmrProcessingResult.alignmentFailed(
      markersFound: 0,
      reason: 'Could not decode image file.',
    );
  }
  return OmrProcessor.process(
    image: decoded,
    template: OmrTemplate.natcoV1(maxQuestionCount: payload.questionCount),
    questionCount: payload.questionCount,
    thresholds: payload.thresholds,
  );
}
