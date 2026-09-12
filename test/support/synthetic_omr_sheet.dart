/// Draws a synthetic NATCO v1 sheet image for tests — no real scanned sheet
/// exists anywhere in this repository (Critical Rule 14), so every OMR test
/// that needs a photo draws its own against the exact template geometry
/// [OmrProcessor] reads. Shared by `omr_processor_test.dart` and
/// `tool/omr_eval.dart`'s own test, so both stay pinned to one drawing.
library;

import 'dart:math' show Point;

import 'package:image/image.dart' as img;
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';

const int syntheticSheetWidth = 500;
const int syntheticSheetHeight = 707; // A4 ratio, matching OmrTemplate.natcoV1
const int syntheticSheetMargin = 40;

/// White background, four corner markers (bottom-left notched unless
/// [notchBottomLeft] is false), the `omrId` bubble grid, and
/// [questionAnswers] filled in (an empty list = blank, two letters =
/// multiple mark).
img.Image buildSyntheticOmrSheet({
  required OmrTemplate template,
  required String omrId,
  required Map<int, List<String>> questionAnswers,
  bool notchBottomLeft = true,
}) {
  final img.Image image = img.Image(
    width: syntheticSheetWidth + syntheticSheetMargin * 2,
    height: syntheticSheetHeight + syntheticSheetMargin * 2,
  );
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 255, 255, 255);
    }
  }

  Point<double> toPixel(Point<double> normalised) => Point<double>(
    syntheticSheetMargin + normalised.x * syntheticSheetWidth,
    syntheticSheetMargin + normalised.y * syntheticSheetHeight,
  );

  final int markerHalf =
      (template.markerSizeFraction * syntheticSheetWidth / 2).round();
  void drawMarker(Point<double> normalisedCenter, {bool notch = false}) {
    final Point<double> c = toPixel(normalisedCenter);
    final int cx = c.x.round(), cy = c.y.round();
    for (int y = cy - markerHalf; y <= cy + markerHalf; y++) {
      for (int x = cx - markerHalf; x <= cx + markerHalf; x++) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixelRgb(x, y, 0, 0, 0);
        }
      }
    }
    if (notch) {
      // A bite out of the corner facing the sheet's centre — same asymmetry
      // docs/07 describes, cutting fill ratio without shrinking the bbox.
      final int notchHalf = (markerHalf * 0.45).round();
      final int nx = cx + (markerHalf * 0.55).round();
      final int ny = cy - (markerHalf * 0.55).round();
      for (int y = ny - notchHalf; y <= ny + notchHalf; y++) {
        for (int x = nx - notchHalf; x <= nx + notchHalf; x++) {
          if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
            image.setPixelRgb(x, y, 255, 255, 255);
          }
        }
      }
    }
  }

  drawMarker(template.markerTopLeft);
  drawMarker(template.markerTopRight);
  drawMarker(template.markerBottomRight);
  drawMarker(template.markerBottomLeft, notch: notchBottomLeft);

  final int bubbleRadius =
      (template.bubbleDiameterFraction * syntheticSheetWidth / 2).round();
  void fillDisc(Point<double> normalisedCenter) {
    final Point<double> c = toPixel(normalisedCenter);
    final int r2 = bubbleRadius * bubbleRadius;
    for (int dy = -bubbleRadius; dy <= bubbleRadius; dy++) {
      for (int dx = -bubbleRadius; dx <= bubbleRadius; dx++) {
        if (dx * dx + dy * dy > r2) {
          continue;
        }
        final int x = (c.x + dx).round();
        final int y = (c.y + dy).round();
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixelRgb(x, y, 0, 0, 0);
        }
      }
    }
  }

  for (int i = 0; i < omrId.length && i < template.idColumns; i++) {
    final int digit = int.parse(omrId[i]);
    fillDisc(template.idBubbleCenter(i, digit));
  }

  const List<String> options = <String>['A', 'B', 'C', 'D'];
  for (final MapEntry<int, List<String>> entry in questionAnswers.entries) {
    for (final String option in entry.value) {
      fillDisc(template.answerBubbleCenter(entry.key, options.indexOf(option)));
    }
  }

  return image;
}
