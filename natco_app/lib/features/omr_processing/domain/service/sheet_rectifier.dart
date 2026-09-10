/// Perspective correction and rotation resolution
/// (docs/07-omr-pipeline.md Steps 4-5).
library;

import 'package:image/image.dart' as img;
import 'package:natco_app/features/omr_processing/domain/entity/marker_corner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/marker_detection_result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/entity/point2d.dart';

/// Warps a captured frame onto the template's canonical rectified size,
/// already in the correct absolute orientation.
///
/// Perspective correction is `package:image`'s own `copyRectify` — a
/// bilinear mapping of the detected marker quadrilateral onto the full
/// output image — rather than a hand-rolled projective-homography solver.
/// For the near-rectangular quads a phone photo of a flat sheet produces,
/// bilinear quad interpolation and a true projective transform agree to
/// well within a bubble's radius; reimplementing the latter from scratch
/// would buy accuracy this pipeline cannot yet measure a difference in
/// (docs/10-omr-calibration-testing.md: "no accuracy claim … unless a
/// harness run produced it").
///
/// Orientation is resolved *without* a post-hoc rotation of the rectified
/// image: rotating a non-square canvas by 90°/270° would swap its width and
/// height, breaking every downstream pixel constant the template defines
/// for a fixed `rectifiedWidthPx × rectifiedHeightPx` canvas. Instead, the
/// four detected corners are fed into `copyRectify` in whichever order
/// already produces that orientation directly — the same number of 90°
/// steps [MarkerCorner.rotationStepsTo] would apply, applied to which
/// *detected* corner lands in which *template* corner slot rather than to
/// pixels after the fact. This is the step that keeps a sheet photographed
/// upside down from aligning "successfully" and reading its answer grid
/// silently inverted.
final class SheetRectifier {
  const SheetRectifier();

  img.Image rectify(
    img.Image source, {
    required MarkerDetectionResult detection,
    required OmrTemplate template,
  }) {
    final int rotationSteps = detection.notchQuadrant.rotationStepsTo(
      template.notchCorner,
    );
    const List<MarkerCorner> corners = MarkerCorner.values;

    Point2D detectedCornerFor(MarkerCorner templateCorner) {
      final int sourceIndex =
          (templateCorner.index - rotationSteps + corners.length) %
          corners.length;
      return detection.markersByQuadrant[corners[sourceIndex]]!.centroid;
    }

    return img.copyRectify(
      source,
      topLeft: _toImgPoint(detectedCornerFor(MarkerCorner.topLeft)),
      topRight: _toImgPoint(detectedCornerFor(MarkerCorner.topRight)),
      bottomRight: _toImgPoint(detectedCornerFor(MarkerCorner.bottomRight)),
      bottomLeft: _toImgPoint(detectedCornerFor(MarkerCorner.bottomLeft)),
      interpolation: img.Interpolation.linear,
      toImage: img.Image(
        width: template.rectifiedWidthPx,
        height: template.rectifiedHeightPx,
      ),
    );
  }

  img.Point _toImgPoint(Point2D point) => img.Point(point.x, point.y);
}
