/// The OMR engine (docs/07-omr-pipeline.md, phase 6): marker detection,
/// perspective correction, bubble sampling, answer classification and
/// confidence — steps 3 through 10 of the pipeline, as pure Dart over
/// `package:image`, no camera and no platform channel, exactly like
/// [ImageQualityAnalyzer].
///
/// What this deliberately does **not** claim: no accuracy figure. Nothing in
/// this file, its tests, or anywhere reachable from it may report a
/// measured recognition rate — that requires the calibration harness in
/// docs/10-omr-calibration-testing.md run against real scanned sheets, which
/// do not exist in this environment (Critical Rule 14). What is proven here
/// is narrower and honest: given a photo of a NATCO v1 sheet, this pipeline
/// finds the markers, rectifies the perspective, resolves absolute rotation
/// from the notched marker, samples the known bubble positions and applies
/// the documented decision tree — checked against sheets this test suite
/// draws itself, not against a labelled real-world dataset.
///
/// Two scope notes, both because a device to verify against does not exist
/// here:
///
/// * Marker binarisation uses one global Otsu threshold over the whole
///   working image rather than the windowed adaptive threshold docs/07 §3
///   calls for. A global threshold is what makes a synthetic test image
///   provable without a real photograph's uneven lighting to tune a window
///   size against; swapping in a windowed threshold later changes
///   [_binarise] alone.
/// * Rectified sampling is nearest-neighbour, not bilinear. Simpler, and at
///   the resolutions here (bubbles several pixels wide) the difference is
///   inside the noise a real calibration pass would tune away regardless.
/// * Step 6's per-block local-offset refinement (docs/07 §"Template
///   alignment refinement") is not implemented — the homography alone is
///   what is proven here.
library;

import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';

// --------------------------------------------------------------- geometry

/// A 2D projective transform (3x3, `h33` normalised to 1), solved from 4
/// point correspondences via the standard direct linear transform — the
/// textbook way to compute a homography from four points with no external
/// linear-algebra package.
final class Homography {
  const Homography(this._h);

  /// Solves the homography mapping each `src[i]` to `dst[i]`, for exactly 4
  /// correspondences (a quadrilateral to a quadrilateral).
  factory Homography.fromCorrespondences({
    required List<Point<double>> src,
    required List<Point<double>> dst,
  }) {
    assert(src.length == 4 && dst.length == 4);
    // Two linear equations per correspondence in the 8 unknowns
    // [h11,h12,h13,h21,h22,h23,h31,h32] (h33 == 1):
    //   h11 x + h12 y + h13 - h31 x x' - h32 y x' = x'
    //   h21 x + h22 y + h23 - h31 x y' - h32 y y' = y'
    final List<List<double>> a = <List<double>>[];
    final List<double> b = <double>[];
    for (int i = 0; i < 4; i++) {
      final double x = src[i].x, y = src[i].y;
      final double xp = dst[i].x, yp = dst[i].y;
      a.add(<double>[x, y, 1, 0, 0, 0, -x * xp, -y * xp]);
      b.add(xp);
      a.add(<double>[0, 0, 0, x, y, 1, -x * yp, -y * yp]);
      b.add(yp);
    }
    return Homography(_solveLinearSystem(a, b));
  }

  final List<double> _h; // row-major, length 8: h11..h13, h21..h23, h31, h32

  Point<double> transform(Point<double> p) {
    final double denom = _h[6] * p.x + _h[7] * p.y + 1.0;
    final double safeDenom = denom.abs() < 1e-9 ? 1e-9 : denom;
    final double x = (_h[0] * p.x + _h[1] * p.y + _h[2]) / safeDenom;
    final double y = (_h[3] * p.x + _h[4] * p.y + _h[5]) / safeDenom;
    return Point<double>(x, y);
  }

  /// Gaussian elimination with partial pivoting. `a` is square (n x n), `b`
  /// is length n; returns the solution vector.
  static List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
    final int n = b.length;
    final List<List<double>> m = <List<double>>[
      for (int i = 0; i < n; i++) List<double>.of(a[i])..add(b[i]),
    ];
    for (int col = 0; col < n; col++) {
      int pivot = col;
      for (int row = col + 1; row < n; row++) {
        if (m[row][col].abs() > m[pivot][col].abs()) {
          pivot = row;
        }
      }
      final List<double> tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;
      final double pivotValue = m[col][col].abs() < 1e-12 ? 1e-12 : m[col][col];
      for (int row = 0; row < n; row++) {
        if (row == col) {
          continue;
        }
        final double factor = m[row][col] / pivotValue;
        for (int k = col; k <= n; k++) {
          m[row][k] -= factor * m[col][k];
        }
      }
    }
    return <double>[for (int i = 0; i < n; i++) m[i][n] / m[i][i]];
  }
}

// ------------------------------------------------------------ marker find

final class DetectedMarker {
  const DetectedMarker({required this.center, required this.fillRatio});

  final Point<double> center;

  /// Filled pixel count over its bounding box's area — a plain solid square
  /// reads close to 1.0; the notched marker reads measurably lower, because
  /// the notch removes area without shrinking the bounding box.
  final double fillRatio;
}

/// The four corners in **template role order** — `[topLeft, topRight,
/// bottomRight, bottomLeft]` — once rotation has been resolved from the
/// notch, ready to feed [Homography.fromCorrespondences] directly against
/// the template's own corner order.
final class MarkerDetectionResult {
  const MarkerDetectionResult({
    required this.markersFound,
    this.orderedCorners,
    this.rotationResolved = false,
  });

  final int markersFound;
  final List<Point<double>>? orderedCorners;

  /// Whether the notched marker was confidently identified. `false` means
  /// [orderedCorners] (when non-null) assumes the sheet was already upright
  /// — a best-effort fallback, not a proven orientation.
  final bool rotationResolved;

  bool get sheetAligned => markersFound >= 4 && orderedCorners != null;
}

// ---------------------------------------------------------------- results

final class OmrQuestionReading {
  const OmrQuestionReading({
    required this.questionNumber,
    required this.optionScores,
    required this.machineAnswer,
    required this.machineConfidence,
    required this.machineStatus,
  });

  final int questionNumber;
  final Map<String, double> optionScores;
  final String? machineAnswer;
  final double machineConfidence;
  final DetectionStatus machineStatus;
}

final class OmrProcessingResult {
  const OmrProcessingResult({
    required this.sheetAligned,
    required this.markersFound,
    this.rotationResolved = false,
    this.failureReason,
    this.decodedOmrId,
    this.omrIdReadable = false,
    this.questions = const <OmrQuestionReading>[],
  });

  const OmrProcessingResult.alignmentFailed({
    required int markersFound,
    required String reason,
  }) : this(sheetAligned: false, markersFound: markersFound, failureReason: reason);

  final bool sheetAligned;
  final int markersFound;
  final bool rotationResolved;
  final String? failureReason;
  final String? decodedOmrId;
  final bool omrIdReadable;
  final List<OmrQuestionReading> questions;
}

// -------------------------------------------------------------- processor

const List<String> _kOptionLetters = <String>['A', 'B', 'C', 'D'];

abstract final class OmrProcessor {
  /// Photos larger than this (long edge, px) are downscaled before any of
  /// this runs — matching [ImageQualityAnalyzer]'s reasoning: none of these
  /// steps need full camera resolution, and a low-end phone should not pay
  /// for megapixels of image data on every capture.
  static const int _workingLongEdge = 1200;

  /// The rectified sheet's fixed size — A4's own aspect ratio (1 : 1.414),
  /// large enough that a 5 mm bubble is several pixels wide after warping.
  static const int _canonicalWidth = 600;
  static const int _canonicalHeight = 849;

  static OmrProcessingResult process({
    required img.Image image,
    required OmrTemplate template,
    required int questionCount,
    double imageQualityScore = 1.0,
    ScannerThresholds thresholds = const ScannerThresholds(),
  }) {
    assert(questionCount <= template.maxQuestionCount);

    final img.Image working = _downscale(image);
    final MarkerDetectionResult markers = _detectMarkers(working, template);
    if (!markers.sheetAligned) {
      return OmrProcessingResult.alignmentFailed(
        markersFound: markers.markersFound,
        reason: markers.markersFound < 4
            ? 'Only ${markers.markersFound} of 4 corner markers were found. '
                  'Keep all four corners visible and retake the photo.'
            : 'The sheet could not be aligned.',
      );
    }

    final Homography rectifier = Homography.fromCorrespondences(
      // Canonical (destination) corners -> detected (source) corners: this
      // is the inverse mapping rectification actually samples with, one
      // solve instead of two.
      dst: markers.orderedCorners!,
      src: <Point<double>>[
        const Point<double>(0, 0),
        Point<double>(_canonicalWidth.toDouble(), 0),
        Point<double>(_canonicalWidth.toDouble(), _canonicalHeight.toDouble()),
        Point<double>(0, _canonicalHeight.toDouble()),
      ],
    );
    final img.Image rectified = _rectify(working, rectifier);

    final _IdDecodeResult idResult = _decodeOmrId(rectified, template, thresholds);

    final List<OmrQuestionReading> questions = <OmrQuestionReading>[
      for (int q = 1; q <= questionCount; q++)
        _readQuestion(rectified, template, thresholds, imageQualityScore, q),
    ];

    return OmrProcessingResult(
      sheetAligned: true,
      markersFound: markers.markersFound,
      rotationResolved: markers.rotationResolved,
      decodedOmrId: idResult.digits,
      omrIdReadable: idResult.readable,
      questions: questions,
    );
  }

  static img.Image _downscale(img.Image image) {
    final int longEdge = image.width > image.height ? image.width : image.height;
    if (longEdge <= _workingLongEdge) {
      return image;
    }
    return image.width >= image.height
        ? img.copyResize(image, width: _workingLongEdge, maintainAspect: true)
        : img.copyResize(image, height: _workingLongEdge, maintainAspect: true);
  }

  // ------------------------------------------------------- step 3: markers

  static MarkerDetectionResult _detectMarkers(img.Image image, OmrTemplate template) {
    final double threshold = _otsuThreshold(image);
    final int w = image.width, h = image.height;
    final double bandX = w * 0.4;
    final double bandY = h * 0.4;
    final double minBlobSide =
        (template.markerSizeFraction * w * 0.4).clamp(3.0, w.toDouble());

    // (xStart, xEnd, yStart, yEnd) per corner, in fixed camera-frame order
    // [topLeft, topRight, bottomRight, bottomLeft] — a plain, unrotated
    // labelling of the *photo's own* quadrants, independent of how the
    // sheet itself is oriented within it.
    final List<List<double>> windows = <List<double>>[
      <double>[0, bandX, 0, bandY],
      <double>[w - bandX, w.toDouble(), 0, bandY],
      <double>[w - bandX, w.toDouble(), h - bandY, h.toDouble()],
      <double>[0, bandX, h - bandY, h.toDouble()],
    ];

    final List<bool> visited = List<bool>.filled(w * h, false);
    final List<DetectedMarker?> found = <DetectedMarker?>[];
    for (final List<double> win in windows) {
      found.add(
        _largestComponentIn(
          image,
          threshold: threshold,
          visited: visited,
          xStart: win[0].floor(),
          xEnd: win[1].ceil(),
          yStart: win[2].floor(),
          yEnd: win[3].ceil(),
          minSide: minBlobSide,
        ),
      );
    }

    final int markersFound = found.whereType<DetectedMarker>().length;
    if (markersFound < 4) {
      return MarkerDetectionResult(markersFound: markersFound);
    }

    final List<DetectedMarker> cameraOrder = found.cast<DetectedMarker>();
    int notchIndex = 3; // default: assume already-upright (camera BL = BL)
    double lowestRatio = double.infinity;
    for (int i = 0; i < 4; i++) {
      if (cameraOrder[i].fillRatio < lowestRatio) {
        lowestRatio = cameraOrder[i].fillRatio;
        notchIndex = i;
      }
    }
    // A plain solid marker reads close to 1.0; only a meaningfully lower
    // ratio counts as the notch, otherwise sensor noise on an already-square
    // marker could masquerade as one.
    final bool resolved = lowestRatio < 0.90;
    if (!resolved) {
      notchIndex = 3;
    }

    final List<Point<double>> ordered = <Point<double>>[
      for (int i = 0; i < 4; i++) cameraOrder[(notchIndex + 1 + i) % 4].center,
    ];

    return MarkerDetectionResult(
      markersFound: markersFound,
      orderedCorners: ordered,
      rotationResolved: resolved,
    );
  }

  static double _otsuThreshold(img.Image image) {
    final List<int> histogram = List<int>.filled(256, 0);
    for (final img.Pixel p in image) {
      final int bucket = (p.luminanceNormalized.toDouble() * 255).round().clamp(0, 255);
      histogram[bucket]++;
    }
    final int total = image.width * image.height;
    double sumAll = 0;
    for (int i = 0; i < 256; i++) {
      sumAll += i * histogram[i];
    }
    double sumBackground = 0;
    int weightBackground = 0;
    double bestVariance = -1;
    int bestThreshold = 128;
    for (int t = 0; t < 256; t++) {
      weightBackground += histogram[t];
      if (weightBackground == 0) {
        continue;
      }
      final int weightForeground = total - weightBackground;
      if (weightForeground == 0) {
        break;
      }
      sumBackground += t * histogram[t];
      final double meanBackground = sumBackground / weightBackground;
      final double meanForeground = (sumAll - sumBackground) / weightForeground;
      final double variance = weightBackground *
          weightForeground *
          (meanBackground - meanForeground) *
          (meanBackground - meanForeground);
      if (variance > bestVariance) {
        bestVariance = variance;
        bestThreshold = t;
      }
    }
    // The loop above picks the last bucket still counted as "background" —
    // the actual separating value sits between that bucket and the next, so
    // biasing by half a bucket keeps a pixel exactly at the dark cluster's
    // own value (as a solid black marker draws) strictly below the
    // threshold, rather than exactly on its boundary.
    return (bestThreshold + 0.5) / 255.0;
  }

  static DetectedMarker? _largestComponentIn(
    img.Image image, {
    required double threshold,
    required List<bool> visited,
    required int xStart,
    required int xEnd,
    required int yStart,
    required int yEnd,
    required double minSide,
  }) {
    final int w = image.width, h = image.height;
    xStart = xStart.clamp(0, w - 1);
    xEnd = xEnd.clamp(1, w);
    yStart = yStart.clamp(0, h - 1);
    yEnd = yEnd.clamp(1, h);

    List<int>? bestMembers;
    int bestSize = 0;
    for (int y = yStart; y < yEnd; y++) {
      for (int x = xStart; x < xEnd; x++) {
        final int idx = y * w + x;
        if (visited[idx]) {
          continue;
        }
        if (image.getPixel(x, y).luminanceNormalized.toDouble() >= threshold) {
          visited[idx] = true;
          continue;
        }
        // Flood fill this component, contained to the search window.
        final List<int> stack = <int>[idx];
        final List<int> members = <int>[];
        visited[idx] = true;
        while (stack.isNotEmpty) {
          final int cur = stack.removeLast();
          members.add(cur);
          final int cx = cur % w, cy = cur ~/ w;
          for (final List<int> d in const <List<int>>[
            <int>[1, 0],
            <int>[-1, 0],
            <int>[0, 1],
            <int>[0, -1],
          ]) {
            final int nx = cx + d[0], ny = cy + d[1];
            if (nx < xStart || nx >= xEnd || ny < yStart || ny >= yEnd) {
              continue;
            }
            final int nIdx = ny * w + nx;
            if (visited[nIdx]) {
              continue;
            }
            if (image.getPixel(nx, ny).luminanceNormalized.toDouble() < threshold) {
              visited[nIdx] = true;
              stack.add(nIdx);
            }
          }
        }
        if (members.length > bestSize) {
          bestSize = members.length;
          bestMembers = members;
        }
      }
    }
    if (bestMembers == null || bestSize < minSide * minSide) {
      return null;
    }
    int minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
    double sumX = 0, sumY = 0;
    for (final int idx in bestMembers) {
      final int x = idx % w, y = idx ~/ w;
      minX = x < minX ? x : minX;
      maxX = x > maxX ? x : maxX;
      minY = y < minY ? y : minY;
      maxY = y > maxY ? y : maxY;
      sumX += x;
      sumY += y;
    }
    final double bboxArea = (maxX - minX + 1) * (maxY - minY + 1);
    return DetectedMarker(
      center: Point<double>(sumX / bestSize, sumY / bestSize),
      fillRatio: bestSize / (bboxArea < 1 ? 1 : bboxArea),
    );
  }

  // --------------------------------------------------- steps 4-5: rectify

  static img.Image _rectify(img.Image source, Homography canonicalToSource) {
    final img.Image out = img.Image(width: _canonicalWidth, height: _canonicalHeight);
    for (int y = 0; y < _canonicalHeight; y++) {
      for (int x = 0; x < _canonicalWidth; x++) {
        final Point<double> src = canonicalToSource.transform(
          Point<double>(x.toDouble(), y.toDouble()),
        );
        final int sx = src.x.round();
        final int sy = src.y.round();
        if (sx < 0 || sx >= source.width || sy < 0 || sy >= source.height) {
          out.setPixelRgb(x, y, 255, 255, 255);
          continue;
        }
        final img.Pixel p = source.getPixel(sx, sy);
        out.setPixelRgb(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt());
      }
    }
    return out;
  }

  // --------------------------------------------------- step 8: sampling

  /// `fillScore = clamp01(meanInkWeight * meanInk + coverageWeight * coverage)`
  /// (docs/07 §"Step 8 — Bubble sampling"), sampling a disc at
  /// [BubbleThresholds.samplingDiameterRatio] of the nominal bubble diameter
  /// with the local background taken from a surrounding annulus, so a
  /// shadowed corner of the sheet is judged against its own lighting rather
  /// than the whole page's.
  static double _sampleFillScore(
    img.Image rectified,
    Point<double> centerNormalised,
    double diameterFractionOfWidth,
    BubbleThresholds bubbles,
  ) {
    final double cx = centerNormalised.x * _canonicalWidth;
    final double cy = centerNormalised.y * _canonicalHeight;
    final double diameterPx = diameterFractionOfWidth * _canonicalWidth;
    final double discRadius = diameterPx * 0.5 * bubbles.samplingDiameterRatio;
    final double annulusInner = diameterPx * 0.6;
    final double annulusOuter = diameterPx * 0.9;

    final List<double> discLum = <double>[];
    final List<double> annulusLum = <double>[];
    final int reach = annulusOuter.ceil() + 1;
    for (int dy = -reach; dy <= reach; dy++) {
      for (int dx = -reach; dx <= reach; dx++) {
        final int x = (cx + dx).round();
        final int y = (cy + dy).round();
        if (x < 0 || x >= rectified.width || y < 0 || y >= rectified.height) {
          continue;
        }
        final double dist = math.sqrt((dx * dx + dy * dy).toDouble());
        final double lum = rectified.getPixel(x, y).luminanceNormalized.toDouble();
        if (dist <= discRadius) {
          discLum.add(lum);
        } else if (dist >= annulusInner && dist <= annulusOuter) {
          annulusLum.add(lum);
        }
      }
    }
    if (discLum.isEmpty) {
      return 0;
    }
    final double background = annulusLum.isEmpty
        ? 1.0
        : _median(annulusLum).clamp(0.05, 1.0);
    final double meanLum = discLum.reduce((double a, double b) => a + b) / discLum.length;
    final double meanInk = (1 - meanLum / background).clamp(0.0, 1.0);
    final double localThreshold = background * 0.7;
    final int covered = discLum.where((double l) => l < localThreshold).length;
    final double coverage = covered / discLum.length;
    final double score =
        bubbles.meanInkWeight * meanInk + bubbles.coverageWeight * coverage;
    return score.clamp(0.0, 1.0);
  }

  static double _median(List<double> values) {
    final List<double> sorted = List<double>.of(values)..sort();
    final int mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  // ------------------------------------------------ step 9-10: classify

  /// The literal decision tree from docs/07-omr-pipeline.md, Step 9. Note:
  /// that document's own worked-example table includes a row (A=0.72,
  /// B=0.69, C=0.10, D=0.08) it labels `LOW_CONFIDENCE`, which is
  /// inconsistent with the tree printed immediately above it in the same
  /// document — that tree's `top2 >= multipleMarkThreshold` branch fires
  /// first for that row (0.69 >= 0.55), which is `MULTIPLE_MARK`. Implemented
  /// here exactly as the tree reads, since that is the executable form of
  /// the spec; the table's row looks like a stale example carried over from
  /// an earlier draft, not a distinction this implementation is missing.
  static (String? answer, DetectionStatus status) _classify(
    Map<String, double> optionScores,
    BubbleThresholds bubbles,
  ) {
    final List<MapEntry<String, double>> sorted = optionScores.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    final double top1 = sorted[0].value;
    final double top2 = sorted.length > 1 ? sorted[1].value : 0.0;
    final String argmax = sorted[0].key;

    if (top1 < bubbles.blankThreshold) {
      return (null, DetectionStatus.blank);
    }
    if (top2 >= bubbles.multipleMarkThreshold) {
      return (null, DetectionStatus.multipleMark);
    }
    if ((top1 - top2) >= bubbles.clearMargin && top1 >= bubbles.filledThreshold) {
      return (argmax, DetectionStatus.highConfidence);
    }
    if ((top1 - top2) >= bubbles.ambiguousMargin) {
      return (argmax, DetectionStatus.mediumConfidence);
    }
    return (argmax, DetectionStatus.lowConfidence);
  }

  static OmrQuestionReading _readQuestion(
    img.Image rectified,
    OmrTemplate template,
    ScannerThresholds thresholds,
    double imageQualityScore,
    int questionNumber,
  ) {
    final Map<String, double> optionScores = <String, double>{
      for (int i = 0; i < 4; i++)
        _kOptionLetters[i]: _sampleFillScore(
          rectified,
          template.answerBubbleCenter(questionNumber, i),
          template.bubbleDiameterFraction,
          thresholds.bubbles,
        ),
    };
    final (String? answer, DetectionStatus status) = _classify(
      optionScores,
      thresholds.bubbles,
    );
    final List<double> sortedScores = optionScores.values.toList()
      ..sort((double a, double b) => b.compareTo(a));
    final double confidence = thresholds.confidence.score(
      topScore: sortedScores[0],
      runnerUpScore: sortedScores.length > 1 ? sortedScores[1] : 0.0,
      imageQualityScore: imageQualityScore,
    );
    return OmrQuestionReading(
      questionNumber: questionNumber,
      optionScores: optionScores,
      machineAnswer: answer,
      machineConfidence: confidence,
      machineStatus: status,
    );
  }

  // -------------------------------------------------------- step 7: id

  static _IdDecodeResult _decodeOmrId(
    img.Image rectified,
    OmrTemplate template,
    ScannerThresholds thresholds,
  ) {
    final StringBuffer digits = StringBuffer();
    for (int column = 0; column < template.idColumns; column++) {
      final Map<String, double> perDigit = <String, double>{
        for (int digit = 0; digit < template.idDigitsPerColumn; digit++)
          '$digit': _sampleFillScore(
            rectified,
            template.idBubbleCenter(column, digit),
            template.bubbleDiameterFraction,
            thresholds.bubbles,
          ),
      };
      final (String? answer, DetectionStatus status) = _classify(
        perDigit,
        thresholds.bubbles,
      );
      // docs/07 Step 7: only a single, high-confidence digit per column
      // counts — anything else makes the whole id unreadable rather than
      // guessed, since a guessed id could attach a sheet to the wrong
      // student.
      if (answer == null || status != DetectionStatus.highConfidence) {
        return const _IdDecodeResult(digits: null, readable: false);
      }
      digits.write(answer);
    }
    return _IdDecodeResult(digits: digits.toString(), readable: true);
  }
}

final class _IdDecodeResult {
  const _IdDecodeResult({required this.digits, required this.readable});
  final String? digits;
  final bool readable;
}
