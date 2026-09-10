/// Output of Step 3 (docs/07-omr-pipeline.md) — the four registration
/// markers located in a captured, not-yet-rectified frame.
library;

import 'package:natco_app/features/omr_processing/domain/entity/marker_corner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/point2d.dart';

/// One located marker: its centroid in the source frame, and how solid its
/// square is (`area ÷ bounding-box area`) — the signal
/// [MarkerDetectionResult.notchQuadrant] uses to tell the notched marker
/// from the three plain ones (docs/07-omr-pipeline.md Steps 4-5).
final class DetectedMarker {
  const DetectedMarker({required this.centroid, required this.fillRatio});

  final Point2D centroid;
  final double fillRatio;
}

/// The four markers, indexed by which quadrant of the *source frame* they
/// were found in — not yet by their true printed identity, which
/// [notchQuadrant] resolves.
final class MarkerDetectionResult {
  const MarkerDetectionResult({required this.markersByQuadrant});

  /// Exactly one entry per [MarkerCorner], keyed by the quadrant of the
  /// captured frame the marker was found in.
  final Map<MarkerCorner, DetectedMarker> markersByQuadrant;

  /// The quadrant whose marker has the lowest fill ratio — a notch removes
  /// material from an otherwise-solid square, so the notched marker is
  /// reliably less filled than the other three (a difference deliberately
  /// exaggerated in the printed template so it survives compression and
  /// blur; see `MarkerDetector`'s own doc comment for the calibratable
  /// margin this identification requires).
  MarkerCorner get notchQuadrant => markersByQuadrant.entries
      .reduce(
        (MapEntry<MarkerCorner, DetectedMarker> a, MapEntry<MarkerCorner, DetectedMarker> b) =>
            a.value.fillRatio <= b.value.fillRatio ? a : b,
      )
      .key;

  /// Corners in the clockwise order Heckbert's quad-mapping formula expects:
  /// top-left, top-right, bottom-right, bottom-left of the *source frame*.
  List<Point2D> get cornersClockwise => <Point2D>[
    markersByQuadrant[MarkerCorner.topLeft]!.centroid,
    markersByQuadrant[MarkerCorner.topRight]!.centroid,
    markersByQuadrant[MarkerCorner.bottomRight]!.centroid,
    markersByQuadrant[MarkerCorner.bottomLeft]!.centroid,
  ];
}
