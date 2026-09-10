/// The OMR calibration/accuracy harness (docs/10-omr-calibration-testing.md
/// §2): `dart run tool/omr_eval.dart`.
///
/// Runs the real pipeline — the same `OmrProcessingPipeline` the app uses,
/// at the same `templateVersion` — over a dataset and writes
/// `reports/<timestamp>/summary.json`, `per_sheet.csv`, `per_question.csv`
/// and `confusion.csv`.
///
/// **What this run actually measures, and what it does not**
/// (docs/10-omr-calibration-testing.md §6, "honest reporting"): there is no
/// `omr_dataset/` of flatbed scans or field photographs available in this
/// environment — no external bucket, no Git LFS checkout. Every image this
/// run scores is generated in-process by `renderSyntheticSheet` with known
/// ground truth, covering only the degradations that generator can produce
/// (rotation, blur, low light, JPEG compression). Every metric below is
/// real and was actually measured against those images; nothing is
/// interpolated or guessed for field cases the dataset doesn't have. A
/// number from this run says "the algorithm reads a rendering of a clean
/// sheet correctly" — it says nothing about a photograph taken in a real
/// classroom, and the summary this script writes states that explicitly
/// rather than presenting a synthetic-only number as field-validated
/// accuracy. Per-stage timings are also unmeasured: nothing in the pipeline
/// exposes stage-boundary hooks yet, so only total per-sheet time is
/// reported.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/entity/question_detection_result.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processing_pipeline.dart';

import 'synthetic_omr_sheet.dart';

/// One synthetic case: a sheet's ground truth and how it was degraded.
final class _Case {
  const _Case({
    required this.id,
    required this.category,
    required this.severity,
    required this.groundTruth,
    required this.jpegBytes,
  });

  final String id;
  final String category;
  final String severity;

  /// questionNumber -> ground truth label: an option letter, `BLANK`, or
  /// `MULTIPLE`.
  final Map<int, String> groundTruth;
  final Uint8List jpegBytes;
}

const List<String> _optionLetters = <String>['A', 'B', 'C', 'D'];

List<_Case> _buildDataset(OmrTemplate template) {
  final List<_Case> cases = <_Case>[];

  img.Image render(Map<int, List<int>> filled) =>
      renderSyntheticSheet(template, filledOptions: filled).image;

  Uint8List jpeg(img.Image image, {int quality = 92}) =>
      Uint8List.fromList(img.encodeJpg(image, quality: quality));

  Map<int, String> truthOf(Map<int, List<int>> filled, int questionCount) => <int, String>{
    for (int q = 1; q <= questionCount; q++)
      q: switch (filled[q]) {
        null || [] => 'BLANK',
        [final int single] => _optionLetters[single],
        _ => 'MULTIPLE',
      },
  };

  // A handful of representative answer patterns, reused across
  // degradations so the same ground truth is scored under each condition.
  final Map<int, List<int>> pattern = <int, List<int>>{
    1: <int>[0],
    2: <int>[1],
    3: <int>[2],
    4: <int>[3],
    5: <int>[], // blank
    6: <int>[0, 2], // multiple
    7: <int>[1],
    8: <int>[],
    9: <int>[3],
    10: <int>[0, 1, 2], // multiple, three marks
  };
  const int questionCount = 10;
  final Map<int, String> truth = truthOf(pattern, questionCount);

  void add(String id, String category, String severity, img.Image image) {
    cases.add(
      _Case(
        id: id,
        category: category,
        severity: severity,
        groundTruth: truth,
        jpegBytes: jpeg(image),
      ),
    );
  }

  add('clean-01', 'clean', 'none', render(pattern));
  add('clean-02', 'clean', 'none', render(pattern));

  add('rotation-01', 'rotation', '1deg', img.copyRotate(render(pattern), angle: 1));
  add('rotation-02', 'rotation', '5deg', img.copyRotate(render(pattern), angle: 5));
  add('rotation-03', 'rotation', '15deg', img.copyRotate(render(pattern), angle: -15));
  add('rotation-04', 'rotation', '90deg', img.copyRotate(render(pattern), angle: 90));
  add('rotation-05', 'rotation', '180deg', img.copyRotate(render(pattern), angle: 180));
  add('rotation-06', 'rotation', '270deg', img.copyRotate(render(pattern), angle: 270));

  add('blur-01', 'blur', 'mild', img.gaussianBlur(render(pattern), radius: 2));
  add('blur-02', 'blur', 'severe', img.gaussianBlur(render(pattern), radius: 5));

  add(
    'low-light-01',
    'low_light',
    'mild',
    img.adjustColor(render(pattern), brightness: 0.75),
  );
  add(
    'low-light-02',
    'low_light',
    'severe',
    img.adjustColor(render(pattern), brightness: 0.55),
  );

  cases.add(
    _Case(
      id: 'compression-01',
      category: 'jpeg_compression',
      severity: 'severe',
      groundTruth: truth,
      jpegBytes: jpeg(render(pattern), quality: 30),
    ),
  );

  return cases;
}

final class _QuestionOutcome {
  const _QuestionOutcome({
    required this.caseId,
    required this.category,
    required this.severity,
    required this.questionNumber,
    required this.truth,
    required this.machine,
    required this.status,
    required this.confidence,
  });

  final String caseId;
  final String category;
  final String severity;
  final int questionNumber;
  final String truth;

  /// The option letter, `BLANK`, or `MULTIPLE` — the same label space as
  /// [truth], so the two are directly comparable.
  final String machine;
  final DetectionStatus? status;
  final double? confidence;

  bool get isCorrect => truth == machine;
}

String _machineLabelOf(QuestionDetectionResult r) => switch (r.machineStatus) {
  DetectionStatus.blank => 'BLANK',
  DetectionStatus.multipleMark => 'MULTIPLE',
  DetectionStatus.unreadable => 'UNREADABLE',
  DetectionStatus.highConfidence ||
  DetectionStatus.mediumConfidence ||
  DetectionStatus.lowConfidence => r.machineAnswer ?? 'UNREADABLE',
};

Future<void> main() async {
  final OmrTemplate template = OmrTemplate.fromJsonString(
    File('assets/omr_templates/natco_v1.json').readAsStringSync(),
  );
  const OmrProcessingPipeline pipeline = OmrProcessingPipeline();
  const ScannerThresholds thresholds = ScannerThresholds();

  final List<_Case> dataset = _buildDataset(template);
  final List<_QuestionOutcome> outcomes = <_QuestionOutcome>[];
  final List<Map<String, Object?>> perSheetRows = <Map<String, Object?>>[];
  int processingFailures = 0;

  for (final _Case testCase in dataset) {
    final Stopwatch stopwatch = Stopwatch()..start();
    final result = pipeline.process(
      testCase.jpegBytes,
      template: template,
      questionCount: testCase.groundTruth.length,
      thresholds: thresholds,
      imageQualityScore: 0.85,
    );
    stopwatch.stop();

    if (result.isFailure) {
      processingFailures++;
      perSheetRows.add(<String, Object?>{
        'id': testCase.id,
        'category': testCase.category,
        'severity': testCase.severity,
        'processed': false,
        'reason': result.failureOrNull?.userMessage,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      continue;
    }

    final outcome = result.valueOrNull!;
    bool sheetFullyCorrect = true;
    for (final QuestionDetectionResult q in outcome.questionResults) {
      final String truth = testCase.groundTruth[q.questionNumber]!;
      final String machine = _machineLabelOf(q);
      final bool correct = truth == machine;
      sheetFullyCorrect &= correct;
      outcomes.add(
        _QuestionOutcome(
          caseId: testCase.id,
          category: testCase.category,
          severity: testCase.severity,
          questionNumber: q.questionNumber,
          truth: truth,
          machine: machine,
          status: q.machineStatus,
          confidence: q.machineConfidence,
        ),
      );
    }
    perSheetRows.add(<String, Object?>{
      'id': testCase.id,
      'category': testCase.category,
      'severity': testCase.severity,
      'processed': true,
      'allQuestionsCorrect': sheetFullyCorrect,
      'needsValidation': outcome.needsValidation,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
  }

  Map<String, Object?> metricsFor(Iterable<_QuestionOutcome> rows) {
    final List<_QuestionOutcome> list = rows.toList();
    if (list.isEmpty) {
      return <String, Object?>{'questionCount': 0};
    }
    final int correct = list.where((_QuestionOutcome o) => o.isCorrect).length;
    final List<_QuestionOutcome> truthBlank = list
        .where((_QuestionOutcome o) => o.truth == 'BLANK')
        .toList();
    final List<_QuestionOutcome> truthOption = list
        .where((_QuestionOutcome o) => _optionLetters.contains(o.truth))
        .toList();
    final List<_QuestionOutcome> truthMultiple = list
        .where((_QuestionOutcome o) => o.truth == 'MULTIPLE')
        .toList();
    final int falsePositives = truthBlank
        .where((_QuestionOutcome o) => o.machine != 'BLANK')
        .length;
    final int falseNegatives = truthOption
        .where((_QuestionOutcome o) => o.machine == 'BLANK')
        .length;
    final List<_QuestionOutcome> highConfidence = list
        .where((_QuestionOutcome o) => o.status == DetectionStatus.highConfidence)
        .toList();
    final int silentErrors = highConfidence
        .where((_QuestionOutcome o) => !o.isCorrect)
        .length;
    final int lowConfidenceCount = list
        .where((_QuestionOutcome o) => o.status == DetectionStatus.lowConfidence)
        .length;
    final int multipleDetectedCorrectly = truthMultiple
        .where((_QuestionOutcome o) => o.machine == 'MULTIPLE')
        .length;
    final int blankDetectedCorrectly = truthBlank
        .where((_QuestionOutcome o) => o.machine == 'BLANK')
        .length;

    return <String, Object?>{
      'questionCount': list.length,
      'perQuestionAccuracy': correct / list.length,
      'falsePositiveRate': truthBlank.isEmpty ? null : falsePositives / truthBlank.length,
      'falseNegativeRate': truthOption.isEmpty ? null : falseNegatives / truthOption.length,
      'blankDetectionRecall': truthBlank.isEmpty
          ? null
          : blankDetectedCorrectly / truthBlank.length,
      'multipleMarkDetectionRecall': truthMultiple.isEmpty
          ? null
          : multipleDetectedCorrectly / truthMultiple.length,
      'lowConfidenceDetectionRate': lowConfidenceCount / list.length,
      'silentErrorRate': highConfidence.isEmpty ? null : silentErrors / highConfidence.length,
      'highConfidenceCount': highConfidence.length,
    };
  }

  final Map<String, Object?> overall = metricsFor(outcomes);
  final Set<String> categories = outcomes.map((_QuestionOutcome o) => o.category).toSet();
  final Map<String, Object?> byCategory = <String, Object?>{
    for (final String category in categories)
      category: metricsFor(outcomes.where((_QuestionOutcome o) => o.category == category)),
  };

  final int sheetsProcessed = perSheetRows.where((Map<String, Object?> r) => r['processed'] == true).length;
  final int sheetsFullyCorrect = perSheetRows
      .where((Map<String, Object?> r) => r['allQuestionsCorrect'] == true)
      .length;

  final List<int> timings = perSheetRows
      .map((Map<String, Object?> r) => r['elapsedMs'] as int)
      .toList()
    ..sort();
  int percentile(double p) =>
      timings.isEmpty ? 0 : timings[(p * (timings.length - 1)).round()];

  final Map<String, Object?> summary = <String, Object?>{
    'datasetRevision': 'in-process synthetic dataset (no omr_dataset/ available)',
    'templateVersion': template.templateVersion,
    'thresholdVersion': thresholds.version,
    'sheetCount': dataset.length,
    'processingFailureCount': processingFailures,
    'sheetAccuracy': dataset.isEmpty ? null : sheetsFullyCorrect / dataset.length,
    'sheetsProcessed': sheetsProcessed,
    'overall': overall,
    'byCategory': byCategory,
    'stageTimingsMs': <String, Object?>{
      'p50Total': percentile(0.5),
      'p95Total': percentile(0.95),
      'note': 'total per-sheet time only; no per-stage timing hooks exist yet',
    },
    'omrIdDecodeRate': 'unmeasured — ID decode is deliberately deferred (docs/08-mvp-implementation-plan.md Phase 6 notes)',
    'validationEfficiency': 'unmeasured — no human validation loop exists in this environment',
    'fieldAccuracy': 'unmeasured — no field/ or clean/ scanned images are available in this environment; every case above is synthetic',
  };

  final String timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
  final Directory reportDir = Directory('reports/$timestamp');
  reportDir.createSync(recursive: true);

  File('${reportDir.path}/summary.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(summary),
  );

  final StringBuffer perSheetCsv = StringBuffer('id,category,severity,processed,allQuestionsCorrect,needsValidation,elapsedMs,reason\n');
  for (final Map<String, Object?> row in perSheetRows) {
    perSheetCsv.writeln(
      <Object?>[
        row['id'],
        row['category'],
        row['severity'],
        row['processed'],
        row['allQuestionsCorrect'] ?? '',
        row['needsValidation'] ?? '',
        row['elapsedMs'],
        row['reason'] ?? '',
      ].join(','),
    );
  }
  File('${reportDir.path}/per_sheet.csv').writeAsStringSync(perSheetCsv.toString());

  final StringBuffer perQuestionCsv = StringBuffer('caseId,category,severity,questionNumber,truth,machine,status,confidence\n');
  for (final _QuestionOutcome o in outcomes) {
    perQuestionCsv.writeln(
      '${o.caseId},${o.category},${o.severity},${o.questionNumber},${o.truth},'
      '${o.machine},${o.status?.wireName ?? ''},${o.confidence ?? ''}',
    );
  }
  File('${reportDir.path}/per_question.csv').writeAsStringSync(perQuestionCsv.toString());

  final List<String> labels = <String>['A', 'B', 'C', 'D', 'BLANK', 'MULTIPLE', 'UNREADABLE'];
  final Map<String, Map<String, int>> confusion = <String, Map<String, int>>{
    for (final String truthLabel in labels)
      truthLabel: <String, int>{for (final String machineLabel in labels) machineLabel: 0},
  };
  for (final _QuestionOutcome o in outcomes) {
    confusion[o.truth]?.update(o.machine, (int v) => v + 1, ifAbsent: () => 1);
  }
  final StringBuffer confusionCsv = StringBuffer('truth\\machine,${labels.join(',')}\n');
  for (final String truthLabel in labels) {
    confusionCsv.writeln(
      '$truthLabel,${labels.map((String m) => confusion[truthLabel]![m]).join(',')}',
    );
  }
  File('${reportDir.path}/confusion.csv').writeAsStringSync(confusionCsv.toString());

  stdout.writeln('OMR calibration harness — synthetic dataset only, see summary.json for caveats.');
  stdout.writeln('Sheets: ${dataset.length} ($processingFailures processing failures)');
  stdout.writeln('Per-question accuracy (overall): ${overall['perQuestionAccuracy']}');
  stdout.writeln('Sheet accuracy: ${summary['sheetAccuracy']}');
  stdout.writeln('Silent error rate (overall): ${overall['silentErrorRate']}');
  stdout.writeln('Report written to ${reportDir.path}/');
}
