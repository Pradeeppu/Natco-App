/// The golden-dataset accuracy harness (docs/10-omr-calibration-testing.md).
///
/// ```
/// dart run tool/omr_eval.dart --dataset omr_dataset [--thresholds config/thresholds.json]
/// ```
///
/// Reads `<dataset>/manifest.json` (a JSON array of sheets, each `{id, image,
/// omrId, answers}` — `answers` is one ground-truth label per question, in
/// order: `A`/`B`/`C`/`D`/`BLANK`/`MULTIPLE`/`DAMAGED`, where `DAMAGED` means
/// the true answer is unknowable and that question is excluded from every
/// metric rather than scored as wrong), runs the real [OmrProcessor] — the
/// same pipeline the app uses — over every listed image, and writes
/// `<dataset>/reports/<timestamp>/summary.json`, `per_sheet.csv`,
/// `per_question.csv` and `confusion.csv`.
///
/// **This file writes no accuracy claim by itself.** It only produces a
/// number when it is actually run against real images with real ground
/// truth; there is no `omr_dataset/` in this repository (Critical Rule 14),
/// so running it here would find no manifest and report nothing. Its own
/// aggregation logic — everything below `main()` — is pure Dart and is
/// proven correct against a tiny synthetic dataset in
/// `test/tool/omr_eval_test.dart`, which is a test of the harness's own
/// arithmetic, not a measured accuracy figure for the scanner.
///
/// One limitation honestly noted rather than faked: docs/10 §3 asks for
/// per-*stage* timings (decode, markers, rectify, ...). [OmrProcessor]
/// exposes no per-stage instrumentation, so this harness reports only total
/// per-sheet wall-clock time — `summary.json` says so explicitly rather than
/// inventing a stage breakdown. Rendered failure overlays (docs/10 §2) are
/// also not built here; `per_question.csv` and `confusion.csv` carry enough
/// to find every disagreement by hand, but nothing draws on the image itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processor.dart';
import 'package:path/path.dart' as p;

// -------------------------------------------------------------- manifest

/// One sheet's entry from `manifest.json`, with its ground truth.
final class ManifestEntry {
  const ManifestEntry({
    required this.id,
    required this.imagePath,
    required this.omrId,
    required this.answers,
  });

  final String id;

  /// Relative to the dataset root, e.g. `images/synthetic/sheet_001.png`.
  final String imagePath;
  final String omrId;

  /// One ground-truth label per question, in order.
  final List<String> answers;

  static ManifestEntry fromJson(Map<String, Object?> json) => ManifestEntry(
    id: json['id']! as String,
    imagePath: json['image']! as String,
    omrId: json['omrId']! as String,
    answers: (json['answers']! as List<dynamic>).cast<String>(),
  );

  static List<ManifestEntry> listFromJson(Object? json) {
    if (json is! List) {
      throw const FormatException('manifest.json must be a JSON array');
    }
    return json
        .cast<Map<String, Object?>>()
        .map(ManifestEntry.fromJson)
        .toList(growable: false);
  }
}

// --------------------------------------------------------- per-question

/// Ground-truth labels that participate in accuracy metrics. `DAMAGED` is a
/// valid manifest label but is deliberately excluded — the true answer is
/// unknowable, so it can be neither correct nor incorrect.
const Set<String> kComparableTruths = <String>{
  'A',
  'B',
  'C',
  'D',
  'BLANK',
  'MULTIPLE',
};

const Set<String> _kLetterTruths = <String>{'A', 'B', 'C', 'D'};

/// One question's ground truth against what the pipeline actually read.
final class QuestionEvalOutcome {
  const QuestionEvalOutcome({
    required this.questionNumber,
    required this.truth,
    required this.reading,
  });

  final int questionNumber;
  final String truth;

  /// `null` when the sheet never aligned, so no reading exists at all.
  final OmrQuestionReading? reading;

  bool get isComparable =>
      kComparableTruths.contains(truth) && reading != null;

  /// The machine's answer, normalised onto the same label set as [truth].
  String get machineLabel {
    final OmrQuestionReading? r = reading;
    if (r == null) {
      return 'UNALIGNED';
    }
    return switch (r.machineStatus) {
      DetectionStatus.blank => 'BLANK',
      DetectionStatus.multipleMark => 'MULTIPLE',
      DetectionStatus.unreadable => 'UNREADABLE',
      _ => r.machineAnswer ?? 'UNREADABLE',
    };
  }

  bool get isCorrect => isComparable && machineLabel == truth;
}

/// One sheet's full evaluation.
final class SheetEvalResult {
  const SheetEvalResult({
    required this.entry,
    required this.result,
    required this.questions,
    required this.elapsed,
  });

  final ManifestEntry entry;
  final OmrProcessingResult result;
  final List<QuestionEvalOutcome> questions;
  final Duration elapsed;

  bool get omrIdDecoded => result.sheetAligned && result.omrIdReadable;
  bool get omrIdCorrect => omrIdDecoded && result.decodedOmrId == entry.omrId;

  List<QuestionEvalOutcome> get comparableQuestions =>
      questions.where((QuestionEvalOutcome q) => q.isComparable).toList(
        growable: false,
      );

  /// A sheet counts as fully correct only if it aligned and every comparable
  /// question on it matched — a sheet with nothing comparable (every answer
  /// `DAMAGED`) counts toward neither the numerator nor the denominator.
  bool get isFullyCorrect =>
      result.sheetAligned &&
      comparableQuestions.isNotEmpty &&
      comparableQuestions.every((QuestionEvalOutcome q) => q.isCorrect);
}

/// Runs the real pipeline against one already-decoded [image] and diffs it
/// against [entry]'s ground truth. Pure — no file I/O — so a test can call
/// it directly against a synthetic sheet.
SheetEvalResult evaluateSheet({
  required ManifestEntry entry,
  required img.Image image,
  ScannerThresholds thresholds = const ScannerThresholds(),
}) {
  final Stopwatch stopwatch = Stopwatch()..start();
  final OmrProcessingResult result = OmrProcessor.process(
    image: image,
    template: OmrTemplate.natcoV1(maxQuestionCount: entry.answers.length),
    questionCount: entry.answers.length,
    thresholds: thresholds,
  );
  stopwatch.stop();

  final Map<int, OmrQuestionReading> byQuestion = <int, OmrQuestionReading>{
    for (final OmrQuestionReading q in result.questions) q.questionNumber: q,
  };
  final List<QuestionEvalOutcome> questions =
      List<QuestionEvalOutcome>.generate(
        entry.answers.length,
        (int i) => QuestionEvalOutcome(
          questionNumber: i + 1,
          truth: entry.answers[i],
          reading: byQuestion[i + 1],
        ),
      );

  return SheetEvalResult(
    entry: entry,
    result: result,
    questions: questions,
    elapsed: stopwatch.elapsed,
  );
}

// -------------------------------------------------------------- summary

/// Aggregate metrics (docs/10 §3). Every field is `double?`/`int?` — `null`
/// means *unmeasured* because the dataset had no case for that metric's
/// denominator, never a fabricated 0 or 1 (docs/10 §6: "it does not
/// interpolate").
final class HarnessSummary {
  const HarnessSummary({
    required this.sheetCount,
    required this.alignedSheetCount,
    required this.comparableQuestionCount,
    required this.perQuestionAccuracy,
    required this.perSheetAccuracy,
    required this.omrIdDecodeRate,
    required this.omrIdErrorRate,
    required this.falsePositiveRate,
    required this.falseNegativeRate,
    required this.blankPrecision,
    required this.blankRecall,
    required this.multipleMarkPrecision,
    required this.multipleMarkRecall,
    required this.lowConfidenceDetectionRate,
    required this.silentErrorRate,
    required this.p50ProcessMillis,
    required this.p95ProcessMillis,
  });

  final int sheetCount;
  final int alignedSheetCount;
  final int comparableQuestionCount;

  final double? perQuestionAccuracy;
  final double? perSheetAccuracy;
  final double? omrIdDecodeRate;
  final double? omrIdErrorRate;
  final double? falsePositiveRate;
  final double? falseNegativeRate;
  final double? blankPrecision;
  final double? blankRecall;
  final double? multipleMarkPrecision;
  final double? multipleMarkRecall;
  final double? lowConfidenceDetectionRate;

  /// The release gate (docs/10 §3): high-confidence answers that are wrong.
  final double? silentErrorRate;

  final int? p50ProcessMillis;
  final int? p95ProcessMillis;

  Map<String, Object?> toJson() => <String, Object?>{
    'sheetCount': sheetCount,
    'alignedSheetCount': alignedSheetCount,
    'comparableQuestionCount': comparableQuestionCount,
    'perQuestionAccuracy': perQuestionAccuracy,
    'perSheetAccuracy': perSheetAccuracy,
    'omrIdDecodeRate': omrIdDecodeRate,
    'omrIdErrorRate': omrIdErrorRate,
    'falsePositiveRate': falsePositiveRate,
    'falseNegativeRate': falseNegativeRate,
    'blankDetectionPrecision': blankPrecision,
    'blankDetectionRecall': blankRecall,
    'multipleMarkDetectionPrecision': multipleMarkPrecision,
    'multipleMarkDetectionRecall': multipleMarkRecall,
    'lowConfidenceDetectionRate': lowConfidenceDetectionRate,
    'silentErrorRate': silentErrorRate,
    'p50ProcessMillis': p50ProcessMillis,
    'p95ProcessMillis': p95ProcessMillis,
  };
}

double? _ratio(int numerator, int denominator) =>
    denominator == 0 ? null : numerator / denominator;

int? _percentile(List<int> sortedAscending, double p) {
  if (sortedAscending.isEmpty) {
    return null;
  }
  final int index = ((sortedAscending.length - 1) * p).round();
  return sortedAscending[index];
}

/// The harness's own arithmetic, pure and independent of file I/O — this is
/// what `test/tool/omr_eval_test.dart` proves against a synthetic dataset.
HarnessSummary summarize(List<SheetEvalResult> results) {
  final List<QuestionEvalOutcome> comparable = <QuestionEvalOutcome>[
    for (final SheetEvalResult r in results) ...r.comparableQuestions,
  ];

  final int truthBlankCount = comparable
      .where((QuestionEvalOutcome q) => q.truth == 'BLANK')
      .length;
  final int falsePositiveCount = comparable
      .where(
        (QuestionEvalOutcome q) =>
            q.truth == 'BLANK' && q.machineLabel != 'BLANK',
      )
      .length;

  final int truthLetterCount = comparable
      .where((QuestionEvalOutcome q) => _kLetterTruths.contains(q.truth))
      .length;
  final int falseNegativeCount = comparable
      .where(
        (QuestionEvalOutcome q) =>
            _kLetterTruths.contains(q.truth) && q.machineLabel == 'BLANK',
      )
      .length;

  final int machineBlankCount = comparable
      .where((QuestionEvalOutcome q) => q.machineLabel == 'BLANK')
      .length;
  final int blankTruePositive = comparable
      .where(
        (QuestionEvalOutcome q) =>
            q.truth == 'BLANK' && q.machineLabel == 'BLANK',
      )
      .length;

  final int truthMultipleCount = comparable
      .where((QuestionEvalOutcome q) => q.truth == 'MULTIPLE')
      .length;
  final int machineMultipleCount = comparable
      .where((QuestionEvalOutcome q) => q.machineLabel == 'MULTIPLE')
      .length;
  final int multipleTruePositive = comparable
      .where(
        (QuestionEvalOutcome q) =>
            q.truth == 'MULTIPLE' && q.machineLabel == 'MULTIPLE',
      )
      .length;

  final int lowConfidenceRoutedCount = comparable
      .where(
        (QuestionEvalOutcome q) =>
            !q.reading!.machineStatus.isAutoAcceptable,
      )
      .length;

  final int highConfidenceCount = comparable
      .where(
        (QuestionEvalOutcome q) =>
            q.reading!.machineStatus == DetectionStatus.highConfidence,
      )
      .length;
  final int highConfidenceWrongCount = comparable
      .where(
        (QuestionEvalOutcome q) =>
            q.reading!.machineStatus == DetectionStatus.highConfidence &&
            !q.isCorrect,
      )
      .length;

  final List<SheetEvalResult> scoreable = results
      .where((SheetEvalResult r) => r.comparableQuestions.isNotEmpty)
      .toList(growable: false);
  final int decodedCount = results
      .where((SheetEvalResult r) => r.omrIdDecoded)
      .length;
  final int decodedWrongCount = results
      .where((SheetEvalResult r) => r.omrIdDecoded && !r.omrIdCorrect)
      .length;

  final List<int> millis =
      results.map((SheetEvalResult r) => r.elapsed.inMilliseconds).toList()
        ..sort();

  return HarnessSummary(
    sheetCount: results.length,
    alignedSheetCount: results
        .where((SheetEvalResult r) => r.result.sheetAligned)
        .length,
    comparableQuestionCount: comparable.length,
    perQuestionAccuracy: _ratio(
      comparable.where((QuestionEvalOutcome q) => q.isCorrect).length,
      comparable.length,
    ),
    perSheetAccuracy: _ratio(
      scoreable.where((SheetEvalResult r) => r.isFullyCorrect).length,
      scoreable.length,
    ),
    omrIdDecodeRate: _ratio(decodedCount, results.length),
    omrIdErrorRate: _ratio(decodedWrongCount, decodedCount),
    falsePositiveRate: _ratio(falsePositiveCount, truthBlankCount),
    falseNegativeRate: _ratio(falseNegativeCount, truthLetterCount),
    blankPrecision: _ratio(blankTruePositive, machineBlankCount),
    blankRecall: _ratio(blankTruePositive, truthBlankCount),
    multipleMarkPrecision: _ratio(multipleTruePositive, machineMultipleCount),
    multipleMarkRecall: _ratio(multipleTruePositive, truthMultipleCount),
    lowConfidenceDetectionRate: _ratio(
      lowConfidenceRoutedCount,
      comparable.length,
    ),
    silentErrorRate: _ratio(highConfidenceWrongCount, highConfidenceCount),
    p50ProcessMillis: _percentile(millis, 0.50),
    p95ProcessMillis: _percentile(millis, 0.95),
  );
}

// ---------------------------------------------------------------- reports

String buildPerSheetCsv(List<SheetEvalResult> results) {
  final StringBuffer buffer = StringBuffer()
    ..writeln(
      'id,sheetAligned,omrIdDecoded,omrIdCorrect,comparableQuestions,'
      'correctQuestions,sheetFullyCorrect,processMillis',
    );
  for (final SheetEvalResult r in results) {
    final int correct = r.comparableQuestions
        .where((QuestionEvalOutcome q) => q.isCorrect)
        .length;
    buffer.writeln(
      <Object?>[
        r.entry.id,
        r.result.sheetAligned,
        r.omrIdDecoded,
        r.omrIdCorrect,
        r.comparableQuestions.length,
        correct,
        r.isFullyCorrect,
        r.elapsed.inMilliseconds,
      ].join(','),
    );
  }
  return buffer.toString();
}

String buildPerQuestionCsv(List<SheetEvalResult> results) {
  final StringBuffer buffer = StringBuffer()
    ..writeln(
      'sheetId,questionNumber,truth,machineLabel,machineConfidence,'
      'comparable,correct',
    );
  for (final SheetEvalResult r in results) {
    for (final QuestionEvalOutcome q in r.questions) {
      buffer.writeln(
        <Object?>[
          r.entry.id,
          q.questionNumber,
          q.truth,
          q.machineLabel,
          q.reading?.machineConfidence ?? '',
          q.isComparable,
          q.isComparable ? q.isCorrect : '',
        ].join(','),
      );
    }
  }
  return buffer.toString();
}

String buildConfusionCsv(List<SheetEvalResult> results) {
  final Set<String> truths = <String>{};
  final Set<String> machineLabels = <String>{};
  final Map<String, Map<String, int>> counts = <String, Map<String, int>>{};
  for (final SheetEvalResult r in results) {
    for (final QuestionEvalOutcome q in r.questions) {
      truths.add(q.truth);
      machineLabels.add(q.machineLabel);
      final Map<String, int> row = counts.putIfAbsent(
        q.truth,
        () => <String, int>{},
      );
      row.update(q.machineLabel, (int v) => v + 1, ifAbsent: () => 1);
    }
  }
  final List<String> truthOrder = truths.toList()..sort();
  final List<String> machineOrder = machineLabels.toList()..sort();

  final StringBuffer buffer = StringBuffer()
    ..writeln(<String>['truth\\machine', ...machineOrder].join(','));
  for (final String truth in truthOrder) {
    final Map<String, int> row = counts[truth] ?? const <String, int>{};
    buffer.writeln(
      <String>[
        truth,
        for (final String m in machineOrder) '${row[m] ?? 0}',
      ].join(','),
    );
  }
  return buffer.toString();
}

// -------------------------------------------------------------------- cli

Map<String, String> _parseFlags(List<String> args) {
  final Map<String, String> flags = <String, String>{};
  for (int i = 0; i < args.length; i++) {
    final String arg = args[i];
    if (arg.startsWith('--') && i + 1 < args.length) {
      flags[arg.substring(2)] = args[++i];
    }
  }
  return flags;
}

Future<void> main(List<String> args) async {
  final Map<String, String> flags = _parseFlags(args);
  final String? datasetPath = flags['dataset'];
  if (datasetPath == null) {
    stderr.writeln(
      'Usage: dart run tool/omr_eval.dart --dataset <dir> '
      '[--thresholds <file>]',
    );
    exitCode = 64;
    return;
  }

  final File manifestFile = File(p.join(datasetPath, 'manifest.json'));
  if (!manifestFile.existsSync()) {
    stderr.writeln('No manifest.json found under $datasetPath.');
    exitCode = 66;
    return;
  }
  final List<ManifestEntry> entries = ManifestEntry.listFromJson(
    jsonDecode(await manifestFile.readAsString()),
  );
  if (entries.isEmpty) {
    stdout.writeln('manifest.json lists no sheets — nothing to measure.');
    return;
  }

  ScannerThresholds thresholds = const ScannerThresholds();
  final String? thresholdsPath = flags['thresholds'];
  if (thresholdsPath != null) {
    final File thresholdsFile = File(thresholdsPath);
    if (!thresholdsFile.existsSync()) {
      stderr.writeln('Thresholds file not found: $thresholdsPath');
      exitCode = 66;
      return;
    }
    final ScannerThresholds? parsed = ScannerThresholds.tryFromJson(
      jsonDecode(await thresholdsFile.readAsString()) as Map<String, Object?>,
    );
    if (parsed == null) {
      stderr.writeln(
        'Thresholds file is inconsistent (e.g. blank threshold >= filled '
        'threshold) — refusing to run with it rather than silently '
        'reclassifying every answer.',
      );
      exitCode = 65;
      return;
    }
    thresholds = parsed;
  }

  final List<SheetEvalResult> results = <SheetEvalResult>[];
  for (final ManifestEntry entry in entries) {
    final File imageFile = File(p.join(datasetPath, entry.imagePath));
    if (!imageFile.existsSync()) {
      stderr.writeln(
        'Skipping ${entry.id}: image not found (${entry.imagePath})',
      );
      continue;
    }
    final img.Image? decoded = img.decodeImage(
      await imageFile.readAsBytes(),
    );
    if (decoded == null) {
      stderr.writeln('Skipping ${entry.id}: could not decode image');
      continue;
    }
    results.add(
      evaluateSheet(entry: entry, image: decoded, thresholds: thresholds),
    );
    stdout.writeln('Processed ${entry.id} (${results.length}/${entries.length})');
  }

  if (results.isEmpty) {
    stdout.writeln('No sheet could be processed — nothing to report.');
    return;
  }

  final HarnessSummary summary = summarize(results);
  final String timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
  final Directory reportDir = Directory(
    p.join(datasetPath, 'reports', timestamp),
  );
  reportDir.createSync(recursive: true);

  File(p.join(reportDir.path, 'summary.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'datasetPath': datasetPath,
      'datasetSheetCount': entries.length,
      'processedSheetCount': results.length,
      'templateVersion': OmrTemplate.natcoV1().templateVersion,
      'thresholdsVersion': thresholds.version,
      'metrics': summary.toJson(),
      'stageTimings':
          'not instrumented per-stage — only total per-sheet wall-clock '
          'time is measured (see per_sheet.csv), see this file\'s own doc '
          'comment',
      'validationEfficiency':
          'unmeasured — this harness runs the automated pipeline only; it '
          'has no human-validation step to compare against',
    }),
  );
  File(
    p.join(reportDir.path, 'per_sheet.csv'),
  ).writeAsStringSync(buildPerSheetCsv(results));
  File(
    p.join(reportDir.path, 'per_question.csv'),
  ).writeAsStringSync(buildPerQuestionCsv(results));
  File(
    p.join(reportDir.path, 'confusion.csv'),
  ).writeAsStringSync(buildConfusionCsv(results));

  stdout.writeln('Report written to ${reportDir.path}');
}
