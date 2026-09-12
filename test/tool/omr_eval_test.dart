/// Tests for `tool/omr_eval.dart`'s own arithmetic: manifest parsing, the
/// per-question/per-sheet diff against ground truth, and the aggregate
/// metrics in [summarize].
///
/// This proves the harness's aggregation math is right against a tiny
/// dataset this file draws itself (three sheets, reusing
/// `buildSyntheticOmrSheet` from `test/support/`) with ground truth chosen to
/// deliberately disagree with what was actually drawn on two of them — the
/// harness has to notice, not just count. **This is not a measured accuracy
/// figure for the scanner** (Critical Rule 14): there is no real scanned
/// sheet involved anywhere in this file, and nothing here is or claims to be
/// a golden-dataset run.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';

import '../../tool/omr_eval.dart';
import '../support/synthetic_omr_sheet.dart';

void main() {
  final OmrTemplate template = OmrTemplate.natcoV1();

  // Sheet A: every ground-truth label agrees with what is actually drawn,
  // plus one DAMAGED question that is never drawn at all — proving DAMAGED
  // is excluded from every metric rather than scored as wrong.
  final img.Image sheetA = buildSyntheticOmrSheet(
    template: template,
    omrId: '1234567',
    questionAnswers: <int, List<String>>{
      1: <String>['A'],
      2: <String>[],
      3: <String>['A', 'B'],
    },
  );
  const ManifestEntry entryA = ManifestEntry(
    id: 'sheet_a',
    imagePath: 'images/sheet_a.png',
    omrId: '1234567',
    answers: <String>['A', 'BLANK', 'MULTIPLE', 'DAMAGED'],
  );

  // Sheet B: drawn as a clean 'C', but the manifest's ground truth says 'D'
  // and gives the wrong omrId — a deliberate silent error and a deliberate
  // omrId mismatch, both of which the harness must catch.
  final img.Image sheetB = buildSyntheticOmrSheet(
    template: template,
    omrId: '7654321',
    questionAnswers: <int, List<String>>{
      1: <String>['C'],
    },
  );
  const ManifestEntry entryB = ManifestEntry(
    id: 'sheet_b',
    imagePath: 'images/sheet_b.png',
    omrId: '0000000',
    answers: <String>['D'],
  );

  // Sheet C: drawn with option A filled, but the manifest says the true
  // answer is BLANK — a deliberate false positive.
  final img.Image sheetC = buildSyntheticOmrSheet(
    template: template,
    omrId: '1112223',
    questionAnswers: <int, List<String>>{
      1: <String>['A'],
    },
  );
  const ManifestEntry entryC = ManifestEntry(
    id: 'sheet_c',
    imagePath: 'images/sheet_c.png',
    omrId: '1112223',
    answers: <String>['BLANK'],
  );

  late List<SheetEvalResult> results;

  setUpAll(() {
    results = <SheetEvalResult>[
      evaluateSheet(entry: entryA, image: sheetA),
      evaluateSheet(entry: entryB, image: sheetB),
      evaluateSheet(entry: entryC, image: sheetC),
    ];
  });

  group('ManifestEntry', () {
    test('round-trips through JSON', () {
      final List<ManifestEntry> parsed = ManifestEntry.listFromJson(
        <Map<String, Object?>>[
          <String, Object?>{
            'id': 'x',
            'image': 'images/x.png',
            'omrId': '1112223',
            'answers': <String>['A', 'BLANK'],
          },
        ],
      );
      expect(parsed, hasLength(1));
      expect(parsed.single.id, 'x');
      expect(parsed.single.omrId, '1112223');
      expect(parsed.single.answers, <String>['A', 'BLANK']);
    });

    test('rejects a manifest that is not a JSON array', () {
      expect(
        () => ManifestEntry.listFromJson(<String, Object?>{'not': 'a list'}),
        throwsFormatException,
      );
    });
  });

  group('evaluateSheet', () {
    test('sheet A: every comparable question matches, DAMAGED is excluded', () {
      final SheetEvalResult a = results[0];
      expect(a.result.sheetAligned, isTrue);
      expect(a.omrIdDecoded, isTrue);
      expect(a.omrIdCorrect, isTrue);
      expect(a.comparableQuestions, hasLength(3));
      expect(
        a.comparableQuestions.every((QuestionEvalOutcome q) => q.isCorrect),
        isTrue,
      );
      expect(a.isFullyCorrect, isTrue);

      final QuestionEvalOutcome damaged = a.questions.firstWhere(
        (QuestionEvalOutcome q) => q.truth == 'DAMAGED',
      );
      expect(
        damaged.isComparable,
        isFalse,
        reason: 'DAMAGED ground truth is unknowable, never scoreable',
      );
    });

    test('sheet B: a confident wrong answer and a wrong omrId are both caught', () {
      final SheetEvalResult b = results[1];
      expect(b.omrIdDecoded, isTrue);
      expect(
        b.omrIdCorrect,
        isFalse,
        reason: 'decoded 7654321 but the manifest said 0000000',
      );
      expect(b.comparableQuestions.single.isCorrect, isFalse);
      expect(b.comparableQuestions.single.machineLabel, 'C');
      expect(b.isFullyCorrect, isFalse);
    });

    test('sheet C: a confidently-filled bubble against a BLANK truth is a '
        'false positive, not a match', () {
      final SheetEvalResult c = results[2];
      expect(c.comparableQuestions.single.truth, 'BLANK');
      expect(c.comparableQuestions.single.machineLabel, 'A');
      expect(c.comparableQuestions.single.isCorrect, isFalse);
    });
  });

  group('summarize', () {
    late HarnessSummary summary;

    setUpAll(() {
      summary = summarize(results);
    });

    test('counts sheets and comparable questions', () {
      expect(summary.sheetCount, 3);
      expect(summary.alignedSheetCount, 3);
      expect(
        summary.comparableQuestionCount,
        5,
        reason: '3 (sheet A) + 1 (B) + 1 (C) — DAMAGED excluded',
      );
    });

    test('per-question and per-sheet accuracy', () {
      expect(summary.perQuestionAccuracy, closeTo(3 / 5, 1e-9));
      expect(summary.perSheetAccuracy, closeTo(1 / 3, 1e-9));
    });

    test('omrId decode rate and error rate', () {
      expect(summary.omrIdDecodeRate, closeTo(1.0, 1e-9));
      expect(
        summary.omrIdErrorRate,
        closeTo(1 / 3, 1e-9),
        reason: 'only sheet B disagreed',
      );
    });

    test('false positive and false negative rates', () {
      // truthBlankCount = 2 (A.Q2, C.Q1); only C.Q1 was a false positive.
      expect(summary.falsePositiveRate, closeTo(0.5, 1e-9));
      // truthLetterCount = 2 (A.Q1, B.Q1); neither was misread as blank.
      expect(summary.falseNegativeRate, closeTo(0.0, 1e-9));
    });

    test('blank and multiple-mark detection precision/recall', () {
      expect(summary.blankPrecision, closeTo(1.0, 1e-9));
      expect(summary.blankRecall, closeTo(0.5, 1e-9));
      expect(summary.multipleMarkPrecision, closeTo(1.0, 1e-9));
      expect(summary.multipleMarkRecall, closeTo(1.0, 1e-9));
    });

    test('low-confidence detection rate and silent error rate', () {
      // Only A.Q3 (MULTIPLE) is routed to validation among the 5 comparable.
      expect(summary.lowConfidenceDetectionRate, closeTo(1 / 5, 1e-9));
      // 3 high-confidence comparable answers (A.Q1, B.Q1, C.Q1); 2 are wrong.
      expect(summary.silentErrorRate, closeTo(2 / 3, 1e-9));
    });

    test('reports timing percentiles, never fabricating a stage breakdown', () {
      expect(summary.p50ProcessMillis, isNotNull);
      expect(summary.p95ProcessMillis, isNotNull);
      expect(summary.p50ProcessMillis, greaterThanOrEqualTo(0));
    });

    test('a metric with no denominator in the dataset is null, not zero', () {
      final HarnessSummary emptyBlank = summarize(
        <SheetEvalResult>[results[1]], // sheet B alone has no BLANK truth
      );
      expect(
        emptyBlank.blankPrecision,
        isNull,
        reason: 'no machine BLANK call exists to take a precision of',
      );
      expect(emptyBlank.blankRecall, isNull);
    });
  });

  group('reports', () {
    test('confusion.csv is a truth x machine label matrix', () {
      final String csv = buildConfusionCsv(results);
      final List<String> lines = csv.trim().split('\n');
      expect(lines.first, 'truth\\machine,A,BLANK,C,MULTIPLE');
      expect(lines, contains('A,1,0,0,0'));
      expect(lines, contains('BLANK,1,1,0,0'));
      expect(lines, contains('D,0,0,1,0'));
      expect(lines, contains('DAMAGED,0,1,0,0'));
      expect(lines, contains('MULTIPLE,0,0,0,1'));
    });

    test('per_sheet.csv has one row per sheet with the right shape', () {
      final List<String> lines = buildPerSheetCsv(
        results,
      ).trim().split('\n');
      expect(lines, hasLength(4)); // header + 3 sheets
      expect(
        lines[0],
        'id,sheetAligned,omrIdDecoded,omrIdCorrect,comparableQuestions,'
        'correctQuestions,sheetFullyCorrect,processMillis',
      );
      final List<String> sheetARow = lines[1].split(',');
      expect(sheetARow.sublist(0, 7), <String>[
        'sheet_a',
        'true',
        'true',
        'true',
        '3',
        '3',
        'true',
      ]);
      expect(int.parse(sheetARow[7]), greaterThanOrEqualTo(0));
    });

    test('per_question.csv has one row per question across all sheets', () {
      final List<String> lines = buildPerQuestionCsv(
        results,
      ).trim().split('\n');
      expect(lines, hasLength(7)); // header + 4 (A) + 1 (B) + 1 (C)
      expect(
        lines.any(
          (String l) => l.startsWith('sheet_a,4,DAMAGED,BLANK,'),
        ),
        isTrue,
        reason: 'DAMAGED still appears in the raw per-question log, just '
            'excluded from the metrics that gate a release',
      );
    });
  });
}
