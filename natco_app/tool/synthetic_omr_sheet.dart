/// Renders a synthetic NATCO v1 sheet with known ground truth.
///
/// Shared by the golden-dataset harness (`tool/omr_eval.dart`) and unit
/// tests, since a real scanned/photographed dataset is not available in
/// this environment (docs/10-omr-calibration-testing.md §1: "synthetic data
/// calibrates, field data decides" — there is no field data here to decide
/// with, which the harness reports plainly as *unmeasured* rather than
/// pretending otherwise, per §6's honest-reporting rule).
library;

import 'package:image/image.dart' as img;
import 'package:natco_app/features/omr_processing/domain/entity/marker_corner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/entity/point2d.dart';

/// Pixels per millimetre used to render a synthetic "captured" sheet at its
/// native, un-rectified resolution — independent of the template's own
/// `rectifiedWidthPx`/`rectifiedHeightPx`, which is the pipeline's *output*
/// canvas, not the input photo's.
const double kSyntheticSheetPxPerMm = 4.0;

/// One rendered sheet plus the ground truth used to render it, so a caller
/// (a test, or the harness) can compare the pipeline's output against
/// exactly what was drawn rather than a separately-maintained expectation.
final class SyntheticSheet {
  const SyntheticSheet({required this.image, required this.filledOptions});

  final img.Image image;

  /// questionNumber -> the option indices filled for it (empty = blank,
  /// more than one = a deliberate multiple-mark case).
  final Map<int, List<int>> filledOptions;
}

/// Renders a synthetic sheet for [template]: four registration markers (one
/// notched, per the template), and the answer grid with [filledOptions]
/// marked in — everything else left blank.
SyntheticSheet renderSyntheticSheet(
  OmrTemplate template, {
  Map<int, List<int>> filledOptions = const <int, List<int>>{},
}) {
  final int width = (template.pageWidthMm * kSyntheticSheetPxPerMm).round();
  final int height = (template.pageHeightMm * kSyntheticSheetPxPerMm).round();
  final img.Image image = img.Image(
    width: width,
    height: height,
    numChannels: 3,
  );
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  final double markerSizePx = template.markerSizeMm * kSyntheticSheetPxPerMm;
  final double insetPx = template.markerInsetMm * kSyntheticSheetPxPerMm;
  final img.Color black = img.ColorRgb8(0, 0, 0);

  final Map<MarkerCorner, Point2D> markerTopLeft = <MarkerCorner, Point2D>{
    MarkerCorner.topLeft: Point2D(insetPx, insetPx),
    MarkerCorner.topRight: Point2D(width - insetPx - markerSizePx, insetPx),
    MarkerCorner.bottomRight: Point2D(
      width - insetPx - markerSizePx,
      height - insetPx - markerSizePx,
    ),
    MarkerCorner.bottomLeft: Point2D(
      insetPx,
      height - insetPx - markerSizePx,
    ),
  };

  for (final MapEntry<MarkerCorner, Point2D> entry in markerTopLeft.entries) {
    _drawMarker(
      image,
      topLeft: entry.value,
      sizePx: markerSizePx,
      notched: entry.key == template.notchCorner,
      color: black,
    );
  }

  final double bubbleRadiusPx =
      (template.bubbleDiameterMm / 2) * kSyntheticSheetPxPerMm;
  for (final AnswerGridColumn column in template.columns) {
    for (
      int q = column.startQuestionNumber;
      q <= column.endQuestionNumber;
      q++
    ) {
      final int row = q - column.startQuestionNumber;
      final List<int> filled = filledOptions[q] ?? const <int>[];
      for (
        int optionIndex = 0;
        optionIndex < template.optionLabels.length;
        optionIndex++
      ) {
        final double xMm =
            column.originXMm + optionIndex * template.optionSpacingMm;
        final double yMm = column.originYMm + row * template.bubblePitchMm;
        final int cx = (xMm * kSyntheticSheetPxPerMm).round();
        final int cy = (yMm * kSyntheticSheetPxPerMm).round();
        if (filled.contains(optionIndex)) {
          img.fillCircle(
            image,
            x: cx,
            y: cy,
            radius: (bubbleRadiusPx * 0.75).round(),
            color: black,
          );
        } else {
          img.drawCircle(
            image,
            x: cx,
            y: cy,
            radius: bubbleRadiusPx.round(),
            color: img.ColorRgb8(160, 160, 160),
          );
        }
      }
    }
  }

  return SyntheticSheet(image: image, filledOptions: filledOptions);
}

/// Draws one solid square marker, optionally with a notch cut from its
/// inner corner (the corner nearest the sheet's centre) — the same
/// asymmetry `MarkerDetector`/`SheetRectifier` rely on to resolve absolute
/// orientation.
void _drawMarker(
  img.Image image, {
  required Point2D topLeft,
  required double sizePx,
  required bool notched,
  required img.Color color,
}) {
  final int x0 = topLeft.x.round();
  final int y0 = topLeft.y.round();
  final int size = sizePx.round();
  img.fillRect(
    image,
    x1: x0,
    y1: y0,
    x2: x0 + size,
    y2: y0 + size,
    color: color,
  );
  if (!notched) {
    return;
  }
  final int notchSize = (sizePx * 0.45).round();
  final bool towardCentreX = image.width / 2 > x0 + size / 2;
  final bool towardCentreY = image.height / 2 > y0 + size / 2;
  final int notchX = towardCentreX ? x0 + size - notchSize : x0;
  final int notchY = towardCentreY ? y0 + size - notchSize : y0;
  img.fillRect(
    image,
    x1: notchX,
    y1: notchY,
    x2: notchX + notchSize,
    y2: notchY + notchSize,
    color: img.ColorRgb8(255, 255, 255),
  );
}
