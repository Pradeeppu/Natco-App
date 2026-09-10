/// Marker detection (docs/07-omr-pipeline.md Step 3).
library;

import 'package:image/image.dart' as img;
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/marker_corner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/marker_detection_result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/point2d.dart';
import 'package:natco_app/features/omr_processing/domain/service/luminance_grid.dart';

/// Fraction of the frame, from each edge, searched for that corner's marker.
/// Generous relative to the template's own ~5% physical inset
/// (docs/07-omr-pipeline.md §1) so the search box comfortably contains the
/// marker even under moderate rotation or perspective, while the two
/// opposite-corner boxes never overlap (0.4 < 0.6 leaves a blank middle).
const double kMarkerSearchFraction = 0.4;

/// How far (in normalised luminance) a pixel must sit below its quadrant's
/// own mean to count as marker ink. Quadrant-local rather than a single
/// image-wide threshold, precisely so a sheet lit unevenly from one side
/// (docs/07-omr-pipeline.md Step 3's stated failure case for a *global*
/// threshold) still gets a locally-correct cut in every corner.
const double kMarkerThresholdOffset = 0.12;

/// A detected blob must be at least this filled (`area ÷ bbox area`) and
/// this square (`min(w,h) / max(w,h)`) to be accepted as a marker rather
/// than incidental dark clutter near a corner.
const double kMinMarkerFillRatio = 0.55;
const double kMinMarkerAspectRatio = 0.55;

/// A blob must also cover at least this fraction of its search box's area.
/// Shape alone (fill ratio, aspect ratio) is not enough: a rasterised circle
/// outline's corner pixels can form a tiny, coincidentally-square 2-4 pixel
/// blob wherever two straight segments meet, which a shape-only test cannot
/// tell from a genuine but small marker. A real marker occupies a
/// predictable, much larger share of its search box (the box is sized off
/// the frame, the marker off the page, and the two are related by the
/// template's own known proportions) — this floor sits an order of
/// magnitude below that expectation, comfortably rejecting rasterisation
/// noise while tolerating real scale variation across devices and
/// distances.
const double kMinMarkerAreaFraction = 0.005;

const Failure _cannotAlign = ValidationFailure(
  userMessage: 'Keep all four corners of the sheet visible and try again.',
);

/// Finds the four square registration markers in a captured, not-yet-
/// rectified frame.
///
/// Deliberately simpler than the doc's literal "sliding-window mean-C"
/// adaptive threshold: because the search is already restricted to four
/// small corner crops (see [kMarkerSearchFraction]), thresholding each crop
/// against *its own* mean luminance gives the same practical benefit — a
/// threshold that tracks local lighting rather than the whole frame's — for
/// a fraction of the arithmetic a full per-pixel sliding window would cost.
final class MarkerDetector {
  const MarkerDetector();

  Result<MarkerDetectionResult> detect(img.Image image) {
    final List<List<double>> luminance = luminanceGridOf(image);
    final int height = luminance.length;
    final int width = height == 0 ? 0 : luminance[0].length;
    if (width == 0 || height == 0) {
      return err(_cannotAlign);
    }

    final Map<MarkerCorner, DetectedMarker> found =
        <MarkerCorner, DetectedMarker>{};
    for (final MarkerCorner corner in MarkerCorner.values) {
      final DetectedMarker? marker = _findMarkerIn(
        luminance,
        corner: corner,
        width: width,
        height: height,
      );
      if (marker == null) {
        return err(_cannotAlign);
      }
      found[corner] = marker;
    }
    return ok(MarkerDetectionResult(markersByQuadrant: found));
  }

  DetectedMarker? _findMarkerIn(
    List<List<double>> luminance, {
    required MarkerCorner corner,
    required int width,
    required int height,
  }) {
    final int boxW = (width * kMarkerSearchFraction).round();
    final int boxH = (height * kMarkerSearchFraction).round();
    final bool left =
        corner == MarkerCorner.topLeft || corner == MarkerCorner.bottomLeft;
    final bool top =
        corner == MarkerCorner.topLeft || corner == MarkerCorner.topRight;
    final int startX = left ? 0 : width - boxW;
    final int startY = top ? 0 : height - boxH;

    double sum = 0;
    int count = 0;
    for (int y = startY; y < startY + boxH; y++) {
      for (int x = startX; x < startX + boxW; x++) {
        sum += luminance[y][x];
        count++;
      }
    }
    if (count == 0) {
      return null;
    }
    final double threshold = sum / count - kMarkerThresholdOffset;

    final List<List<bool>> visited = List<List<bool>>.generate(
      boxH,
      (_) => List<bool>.filled(boxW, false),
    );

    final int minArea = (boxW * boxH * kMinMarkerAreaFraction).round();
    DetectedMarker? best;
    int bestArea = 0;
    for (int y = 0; y < boxH; y++) {
      for (int x = 0; x < boxW; x++) {
        if (visited[y][x] || luminance[startY + y][startX + x] >= threshold) {
          continue;
        }
        final _Blob blob = _floodFill(
          luminance,
          visited: visited,
          startX: x,
          startY: y,
          boxX: startX,
          boxY: startY,
          boxW: boxW,
          boxH: boxH,
          threshold: threshold,
        );
        if (blob.area <= bestArea || blob.area < minArea) {
          continue;
        }
        final int bboxW = blob.maxX - blob.minX + 1;
        final int bboxH = blob.maxY - blob.minY + 1;
        final double fillRatio = blob.area / (bboxW * bboxH);
        final double aspectRatio = bboxW < bboxH
            ? bboxW / bboxH
            : bboxH / bboxW;
        if (fillRatio < kMinMarkerFillRatio ||
            aspectRatio < kMinMarkerAspectRatio) {
          continue;
        }
        bestArea = blob.area;
        best = DetectedMarker(
          centroid: Point2D(
            startX + (blob.minX + blob.maxX) / 2,
            startY + (blob.minY + blob.maxY) / 2,
          ),
          fillRatio: fillRatio,
        );
      }
    }
    return best;
  }

  /// 4-connected flood fill within one corner's search box, tracking the
  /// component's bounding box and area in the same pass — cheap because the
  /// box is a small fraction of the frame (see [kMarkerSearchFraction]).
  _Blob _floodFill(
    List<List<double>> luminance, {
    required List<List<bool>> visited,
    required int startX,
    required int startY,
    required int boxX,
    required int boxY,
    required int boxW,
    required int boxH,
    required double threshold,
  }) {
    int minX = startX;
    int maxX = startX;
    int minY = startY;
    int maxY = startY;
    int area = 0;
    final List<List<int>> stack = <List<int>>[
      <int>[startX, startY],
    ];
    visited[startY][startX] = true;
    while (stack.isNotEmpty) {
      final List<int> point = stack.removeLast();
      final int x = point[0];
      final int y = point[1];
      area++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (final List<int> delta in const <List<int>>[
        <int>[1, 0],
        <int>[-1, 0],
        <int>[0, 1],
        <int>[0, -1],
      ]) {
        final int nx = x + delta[0];
        final int ny = y + delta[1];
        if (nx < 0 || ny < 0 || nx >= boxW || ny >= boxH || visited[ny][nx]) {
          continue;
        }
        if (luminance[boxY + ny][boxX + nx] >= threshold) {
          continue;
        }
        visited[ny][nx] = true;
        stack.add(<int>[nx, ny]);
      }
    }
    return _Blob(minX: minX, maxX: maxX, minY: minY, maxY: maxY, area: area);
  }
}

final class _Blob {
  const _Blob({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.area,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
  final int area;
}
