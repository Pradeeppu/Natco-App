/// The NATCO v1 OMR sheet geometry (docs/07-omr-pipeline.md §1), loaded from
/// `assets/omr_templates/natco_v1.json` rather than hard-coded — a v2 sheet
/// (different option count, question count, or bubble geometry) is a new
/// JSON file plus a `templateVersion` field on the assessment, not a rewrite
/// of this class.
///
/// Stores the answer grid as regular *structural* parameters (each column's
/// origin, a shared row pitch, a shared option spacing) rather than one
/// literal entry per bubble: the grid is perfectly regular, so a formula
/// over these parameters describes exactly the same geometry a fully
/// enumerated array would, with far less JSON to keep in sync by hand. A
/// future irregular template could add an explicit per-bubble override list
/// without changing this class's shape — nothing downstream depends on
/// positions being literal rather than computed.
///
/// Deliberately carries no header/OMR-id bubble grid: the printed `omrId`
/// is already captured by the manual entry Phase 5 built
/// (docs/08-mvp-implementation-plan.md Phase 5 exit criteria). Reading it
/// again from a header bubble grid would duplicate an identity the app
/// already has, for the sake of an accuracy metric on a value that already
/// has a trusted source — not a capability the app is missing.
library;

import 'dart:convert';

import 'package:natco_app/features/omr_processing/domain/entity/marker_corner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/point2d.dart';

final class AnswerGridColumn {
  const AnswerGridColumn({
    required this.startQuestionNumber,
    required this.questionCount,
    required this.originXMm,
    required this.originYMm,
  });

  factory AnswerGridColumn.fromJson(Map<String, dynamic> json) =>
      AnswerGridColumn(
        startQuestionNumber: json['startQuestionNumber'] as int,
        questionCount: json['questionCount'] as int,
        originXMm: (json['originXMm'] as num).toDouble(),
        originYMm: (json['originYMm'] as num).toDouble(),
      );

  final int startQuestionNumber;
  final int questionCount;

  /// mm position, in absolute page coordinates, of this column's first
  /// question's first option bubble.
  final double originXMm;
  final double originYMm;

  int get endQuestionNumber => startQuestionNumber + questionCount - 1;

  bool contains(int questionNumber) =>
      questionNumber >= startQuestionNumber &&
      questionNumber <= endQuestionNumber;
}

final class OmrTemplate {
  const OmrTemplate({
    required this.templateVersion,
    required this.pageWidthMm,
    required this.pageHeightMm,
    required this.markerSizeMm,
    required this.markerInsetMm,
    required this.notchCorner,
    required this.rectifiedWidthPx,
    required this.rectifiedHeightPx,
    required this.bubbleDiameterMm,
    required this.bubblePitchMm,
    required this.optionLabels,
    required this.optionSpacingMm,
    required this.columns,
  });

  factory OmrTemplate.fromJsonString(String source) =>
      OmrTemplate.fromJson(jsonDecode(source) as Map<String, dynamic>);

  factory OmrTemplate.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> grid =
        json['answerGrid'] as Map<String, dynamic>;
    return OmrTemplate(
      templateVersion: json['templateVersion'] as int,
      pageWidthMm: (json['pageWidthMm'] as num).toDouble(),
      pageHeightMm: (json['pageHeightMm'] as num).toDouble(),
      markerSizeMm: (json['markerSizeMm'] as num).toDouble(),
      markerInsetMm: (json['markerInsetMm'] as num).toDouble(),
      notchCorner: MarkerCorner.fromWireName(json['notchCorner'] as String),
      rectifiedWidthPx: json['rectifiedWidthPx'] as int,
      rectifiedHeightPx: json['rectifiedHeightPx'] as int,
      bubbleDiameterMm: (grid['bubbleDiameterMm'] as num).toDouble(),
      bubblePitchMm: (grid['bubblePitchMm'] as num).toDouble(),
      optionLabels: (grid['optionLabels'] as List<dynamic>).cast<String>(),
      optionSpacingMm: (grid['optionSpacingMm'] as num).toDouble(),
      columns: (grid['columns'] as List<dynamic>)
          .map(
            (dynamic c) => AnswerGridColumn.fromJson(c as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final int templateVersion;
  final double pageWidthMm;
  final double pageHeightMm;
  final double markerSizeMm;
  final double markerInsetMm;

  /// Which corner of the printed sheet carries the asymmetric notch that
  /// resolves absolute orientation (docs/07-omr-pipeline.md §1).
  final MarkerCorner notchCorner;

  /// Fixed pixel size every captured sheet is warped to, regardless of the
  /// camera's native resolution — so every downstream bubble position is a
  /// fixed pixel constant computed once, not re-derived per photo.
  final int rectifiedWidthPx;
  final int rectifiedHeightPx;

  final double bubbleDiameterMm;
  final double bubblePitchMm;
  final List<String> optionLabels;
  final double optionSpacingMm;
  final List<AnswerGridColumn> columns;

  /// Distance from the page edge to a marker's centre: markers are inset
  /// [markerInsetMm] from the edge, and a square marker's own centre sits a
  /// further half marker-size in.
  double get _markerCentreInsetMm => markerInsetMm + markerSizeMm / 2;

  /// The physical rectangle spanned by the four marker centres — what a
  /// rectified image's `(0,0)`-`(rectifiedWidthPx,rectifiedHeightPx)` extent
  /// represents (docs/07-omr-pipeline.md Steps 4-5).
  double get _rectWidthMm => pageWidthMm - 2 * _markerCentreInsetMm;
  double get _rectHeightMm => pageHeightMm - 2 * _markerCentreInsetMm;

  int get questionCount =>
      columns.fold(0, (int sum, AnswerGridColumn c) => sum + c.questionCount);

  AnswerGridColumn columnFor(int questionNumber) => columns.firstWhere(
    (AnswerGridColumn c) => c.contains(questionNumber),
    orElse: () => throw ArgumentError(
      'Question $questionNumber is outside this template\'s answer grid '
      '(defines $questionCount questions)',
    ),
  );

  /// Pixel centre, in the rectified canonical image, of one option bubble.
  Point2D bubbleCentrePx({
    required int questionNumber,
    required int optionIndex,
  }) {
    final AnswerGridColumn column = columnFor(questionNumber);
    final int row = questionNumber - column.startQuestionNumber;
    final double xMm = column.originXMm + optionIndex * optionSpacingMm;
    final double yMm = column.originYMm + row * bubblePitchMm;
    final double xNorm = (xMm - _markerCentreInsetMm) / _rectWidthMm;
    final double yNorm = (yMm - _markerCentreInsetMm) / _rectHeightMm;
    return Point2D(xNorm * rectifiedWidthPx, yNorm * rectifiedHeightPx);
  }

  /// Nominal bubble radius in rectified pixels, for the sampling disc in
  /// docs/07-omr-pipeline.md Step 8.
  double bubbleRadiusPx() =>
      (bubbleDiameterMm / 2) / _rectWidthMm * rectifiedWidthPx;
}
