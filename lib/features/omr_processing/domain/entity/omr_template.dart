/// The NATCO v1 sheet's known geometry (docs/07-omr-pipeline.md §1).
///
/// Arbitrary OMR sheets are not supported — the app reads one controlled
/// template whose bubble positions are known at build time, which is what
/// turns "find the bubbles" into "sample known positions after alignment".
/// Every position here is in **normalised template coordinates**: a fraction
/// of the marker rectangle's own width/height, not a pixel constant, so the
/// same geometry applies at any capture resolution once the sheet has been
/// rectified onto a canonical-size image.
///
/// Deliberately a Dart constant rather than a parsed
/// `assets/omr_templates/natco_v1.json` file for this pass: nothing in this
/// environment can exercise loading it any differently (no device to load an
/// asset bundle on), and moving these fields into a JSON file the app parses
/// at startup is a small, isolated change from here — not a redesign. If a
/// v2 sheet (different option count, different layout) is ever needed, that
/// is exactly the moment this stops being a constant.
library;

import 'dart:math' show Point;

final class OmrTemplate {
  const OmrTemplate({
    required this.templateVersion,
    required this.markerTopLeft,
    required this.markerTopRight,
    required this.markerBottomLeft,
    required this.markerBottomRight,
    required this.markerSizeFraction,
    required this.idGridOrigin,
    required this.idColumnPitchFraction,
    required this.idRowPitchFraction,
    required this.idColumns,
    required this.idDigitsPerColumn,
    required this.answerGridOrigin,
    required this.optionColumnPitchFraction,
    required this.questionRowPitchFraction,
    required this.questionsPerColumnBlock,
    required this.columnBlockSpacingFraction,
    required this.bubbleDiameterFraction,
    required this.maxQuestionCount,
  });

  /// NATCO v1 (docs/07 §1): A4, four 12 mm corner markers inset 10 mm, the
  /// bottom-left one notched; a 7-column x 10-row `omrId` bubble grid; an
  /// answer grid of 4-option questions in 25-question columns.
  ///
  /// All fractions below are relative to the marker rectangle (the square
  /// formed by the four marker *centres*), which is exactly what the
  /// homography in [OmrProcessor] rectifies onto — so "normalised" here means
  /// "0.0-1.0 across that rectangle", independent of capture resolution.
  factory OmrTemplate.natcoV1({int maxQuestionCount = 100}) => OmrTemplate(
    templateVersion: 'natco_v1',
    markerTopLeft: const Point<double>(0.0, 0.0),
    markerTopRight: const Point<double>(1.0, 0.0),
    markerBottomLeft: const Point<double>(0.0, 1.0),
    markerBottomRight: const Point<double>(1.0, 1.0),
    markerSizeFraction: 0.045,
    idGridOrigin: const Point<double>(0.62, 0.06),
    idColumnPitchFraction: 0.045,
    idRowPitchFraction: 0.022,
    idColumns: 7,
    idDigitsPerColumn: 10,
    answerGridOrigin: const Point<double>(0.08, 0.30),
    optionColumnPitchFraction: 0.035,
    questionRowPitchFraction: 0.028,
    questionsPerColumnBlock: 25,
    columnBlockSpacingFraction: 0.24,
    bubbleDiameterFraction: 0.024,
    maxQuestionCount: maxQuestionCount,
  );

  final String templateVersion;

  /// The four marker centres, in the rectified rectangle's own normalised
  /// space — by construction always the unit square's corners, since the
  /// rectified image *is* that rectangle. Kept as fields (rather than
  /// hardcoded in [OmrProcessor]) so a future template with a differently
  /// shaped marker rectangle is still just data.
  final Point<double> markerTopLeft;
  final Point<double> markerTopRight;
  final Point<double> markerBottomLeft;
  final Point<double> markerBottomRight;

  /// Marker edge length, as a fraction of the rectified rectangle's width —
  /// used to size the search window when locating markers in the source
  /// (unrectified) photo.
  final double markerSizeFraction;

  /// Top-left bubble centre of the `omrId` grid's first column/row.
  final Point<double> idGridOrigin;
  final double idColumnPitchFraction;
  final double idRowPitchFraction;
  final int idColumns;

  /// 10 — digits 0-9, one bubble per row per column (docs/07 §1, Step 7).
  final int idDigitsPerColumn;

  /// Top-left bubble centre (question 1, option A) of the answer grid.
  final Point<double> answerGridOrigin;

  /// Horizontal spacing between option bubbles (A -> B -> C -> D).
  final double optionColumnPitchFraction;

  /// Vertical spacing between question rows within one column block.
  final double questionRowPitchFraction;

  /// Questions per printed column before wrapping to the next block
  /// (docs/07 §1: "arranged in columns of 25 questions").
  final int questionsPerColumnBlock;

  /// Horizontal spacing between the start of one question-column block and
  /// the next.
  final double columnBlockSpacingFraction;

  final double bubbleDiameterFraction;

  /// The largest question count this template's answer-grid geometry has
  /// room for. [OmrProcessor.process] refuses a [questionCount] beyond this
  /// rather than silently sampling off the printed sheet.
  final int maxQuestionCount;

  /// The bubble centre for option [optionIndex] (0=A, 1=B, 2=C, 3=D) of
  /// 1-indexed [questionNumber], in the template's normalised space.
  Point<double> answerBubbleCenter(int questionNumber, int optionIndex) {
    final int zeroBased = questionNumber - 1;
    final int block = zeroBased ~/ questionsPerColumnBlock;
    final int rowInBlock = zeroBased % questionsPerColumnBlock;
    return Point<double>(
      answerGridOrigin.x +
          block * columnBlockSpacingFraction +
          optionIndex * optionColumnPitchFraction,
      answerGridOrigin.y + rowInBlock * questionRowPitchFraction,
    );
  }

  /// The bubble centre for digit [digit] (0-9) of 0-indexed [column] in the
  /// `omrId` grid.
  Point<double> idBubbleCenter(int column, int digit) => Point<double>(
    idGridOrigin.x + column * idColumnPitchFraction,
    idGridOrigin.y + digit * idRowPitchFraction,
  );
}
