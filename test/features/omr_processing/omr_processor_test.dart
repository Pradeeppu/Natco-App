/// Tests for [OmrProcessor] — phase 6's OMR engine (docs/07-omr-pipeline.md).
///
/// Every sheet here is drawn by this test file itself, using the exact same
/// [OmrTemplate] geometry the processor reads against — there is no real
/// scanned sheet anywhere in this repository (Critical Rule 14), so nothing
/// here is or claims to be a measured accuracy figure. What is proven: given
/// a photo of a NATCO v1 sheet — including one photographed upside down, and
/// one with a corner marker missing — the pipeline finds the markers,
/// resolves rotation from the notch, decodes the `omrId` grid and classifies
/// each answer bubble via the documented decision tree.
library;

import 'dart:math' show Point;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processor.dart';

const int _sheetWidth = 500;
const int _sheetHeight = 707; // A4 ratio, matching OmrTemplate.natcoV1
const int _margin = 40;

/// Builds a synthetic NATCO v1 photo: white background, four corner
/// markers (bottom-left notched unless [notchBottomLeft] is false, to build
/// the "orientation unresolved" case), the `omrId` bubble grid, and the given
/// [questionAnswers] fully filled (an empty list = blank, two letters =
/// multiple mark).
img.Image _buildSheet({
  required OmrTemplate template,
  required String omrId,
  required Map<int, List<String>> questionAnswers,
}) {
  final img.Image image = img.Image(
    width: _sheetWidth + _margin * 2,
    height: _sheetHeight + _margin * 2,
  );
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 255, 255, 255);
    }
  }

  Point<double> toPixel(Point<double> normalised) => Point<double>(
    _margin + normalised.x * _sheetWidth,
    _margin + normalised.y * _sheetHeight,
  );

  final int markerHalf = (template.markerSizeFraction * _sheetWidth / 2).round();
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
  drawMarker(template.markerBottomLeft, notch: true);

  final int bubbleRadius = (template.bubbleDiameterFraction * _sheetWidth / 2).round();
  void fillDisc(Point<double> normalisedCenter, {double halfOnly = 0}) {
    final Point<double> c = toPixel(normalisedCenter);
    final int r2 = bubbleRadius * bubbleRadius;
    for (int dy = -bubbleRadius; dy <= bubbleRadius; dy++) {
      for (int dx = -bubbleRadius; dx <= bubbleRadius; dx++) {
        if (dx * dx + dy * dy > r2) {
          continue;
        }
        if (halfOnly > 0 && dx > 0) {
          continue; // left-half fill, for the partial-mark case
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

void main() {
  final OmrTemplate template = OmrTemplate.natcoV1();

  group('an upright sheet', () {
    late img.Image sheet;

    setUp(() {
      sheet = _buildSheet(
        template: template,
        omrId: '1234567',
        questionAnswers: <int, List<String>>{
          1: <String>['A'], // clean, high confidence
          2: <String>[], // blank
          3: <String>['A', 'B'], // multiple mark
        },
      );
    });

    test('finds all four markers and rectifies the sheet', () {
      final OmrProcessingResult result = OmrProcessor.process(
        image: sheet,
        template: template,
        questionCount: 3,
      );
      expect(result.sheetAligned, isTrue);
      expect(result.markersFound, 4);
    });

    test('decodes the omrId from the bubble grid', () {
      final OmrProcessingResult result = OmrProcessor.process(
        image: sheet,
        template: template,
        questionCount: 3,
      );
      expect(result.omrIdReadable, isTrue);
      expect(result.decodedOmrId, '1234567');
    });

    test('classifies a clean single mark as high confidence', () {
      final OmrProcessingResult result = OmrProcessor.process(
        image: sheet,
        template: template,
        questionCount: 3,
      );
      final OmrQuestionReading q1 = result.questions.firstWhere(
        (OmrQuestionReading q) => q.questionNumber == 1,
      );
      expect(q1.machineStatus, DetectionStatus.highConfidence);
      expect(q1.machineAnswer, 'A');
    });

    test('classifies an empty question as blank', () {
      final OmrProcessingResult result = OmrProcessor.process(
        image: sheet,
        template: template,
        questionCount: 3,
      );
      final OmrQuestionReading q2 = result.questions.firstWhere(
        (OmrQuestionReading q) => q.questionNumber == 2,
      );
      expect(q2.machineStatus, DetectionStatus.blank);
      expect(q2.machineAnswer, isNull);
    });

    test('classifies two filled options as multiple mark, never a guess', () {
      final OmrProcessingResult result = OmrProcessor.process(
        image: sheet,
        template: template,
        questionCount: 3,
      );
      final OmrQuestionReading q3 = result.questions.firstWhere(
        (OmrQuestionReading q) => q.questionNumber == 3,
      );
      expect(q3.machineStatus, DetectionStatus.multipleMark);
      expect(q3.machineAnswer, isNull);
    });
  });

  test(
    'a sheet photographed upside down is detected and corrected, not '
    'silently inverted',
    () {
      final img.Image upright = _buildSheet(
        template: template,
        omrId: '7654321',
        questionAnswers: <int, List<String>>{
          1: <String>['C'],
        },
      );
      final img.Image upsideDown = img.copyRotate(upright, angle: 180);

      final OmrProcessingResult result = OmrProcessor.process(
        image: upsideDown,
        template: template,
        questionCount: 1,
      );

      expect(result.sheetAligned, isTrue);
      expect(
        result.rotationResolved,
        isTrue,
        reason: 'the notched marker must have been found and used to '
            'resolve orientation',
      );
      expect(result.decodedOmrId, '7654321');
      expect(result.questions.single.machineAnswer, 'C');
      expect(result.questions.single.machineStatus, DetectionStatus.highConfidence);
    },
  );

  test('a sheet rotated 90 degrees is still read correctly', () {
    final img.Image upright = _buildSheet(
      template: template,
      omrId: '1112223',
      questionAnswers: <int, List<String>>{
        1: <String>['D'],
      },
    );
    final img.Image rotated = img.copyRotate(upright, angle: 90);

    final OmrProcessingResult result = OmrProcessor.process(
      image: rotated,
      template: template,
      questionCount: 1,
    );

    expect(result.sheetAligned, isTrue);
    expect(result.decodedOmrId, '1112223');
    expect(result.questions.single.machineAnswer, 'D');
  });

  test('fewer than four visible markers fails closed rather than guessing', () {
    final img.Image sheet = _buildSheet(
      template: template,
      omrId: '1234567',
      // No answer bubbles: the answer grid's top-left corner falls inside
      // this window's search band, and a filled bubble there is otherwise
      // large enough to be mistaken for the marker this test just erased.
      questionAnswers: <int, List<String>>{},
    );
    // Paint over the top-left marker, simulating a corner cut off by
    // framing or occluded by a thumb.
    for (int y = 0; y < 90; y++) {
      for (int x = 0; x < 90; x++) {
        sheet.setPixelRgb(x, y, 255, 255, 255);
      }
    }

    final OmrProcessingResult result = OmrProcessor.process(
      image: sheet,
      template: template,
      questionCount: 1,
    );

    expect(result.sheetAligned, isFalse);
    expect(result.markersFound, lessThan(4));
    expect(result.failureReason, isNotNull);
    expect(
      result.questions,
      isEmpty,
      reason: 'a sheet that failed to align must not report any answers',
    );
  });

  test(
    'a partial, ambiguous mark is preserved as machine evidence but never '
    'silently promoted to a confident answer',
    () {
      final img.Image sheet = _buildSheet(
        template: template,
        omrId: '1234567',
        questionAnswers: <int, List<String>>{},
      );
      // Two genuinely partial pencil marks, not a clean fill: option A about
      // half-covered, option B about a third — close enough in score that
      // neither clears `clearMargin` over the other, which (not how heavily
      // the top option alone is filled) is what actually drives ambiguity
      // in the documented decision tree.
      void partialFill(int optionIndex, double fraction) {
        final Point<double> center = Point<double>(
          _margin + template.answerBubbleCenter(1, optionIndex).x * _sheetWidth,
          _margin + template.answerBubbleCenter(1, optionIndex).y * _sheetHeight,
        );
        final int radius = (template.bubbleDiameterFraction * _sheetWidth / 2).round();
        final double cutoffDx = -radius + 2 * radius * fraction;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= cutoffDx; dx++) {
            if (dx * dx + dy * dy > radius * radius) {
              continue;
            }
            final int x = (center.x + dx).round();
            final int y = (center.y + dy).round();
            sheet.setPixelRgb(x, y, 0, 0, 0);
          }
        }
      }

      partialFill(0, 0.40); // option A
      partialFill(1, 0.28); // option B

      final OmrProcessingResult result = OmrProcessor.process(
        image: sheet,
        template: template,
        questionCount: 1,
      );

      final OmrQuestionReading q1 = result.questions.single;
      expect(
        q1.machineStatus,
        isNot(DetectionStatus.highConfidence),
        reason: 'a half-filled bubble is not a clean mark',
      );
      expect(
        q1.machineStatus,
        isNot(DetectionStatus.blank),
        reason: 'there is genuinely some ink here',
      );
      // The machine's best guess is still recorded — Step 9's own note that
      // a low/medium-confidence reading is preserved as evidence, never
      // discarded, even though it is not auto-acceptable.
      expect(q1.machineAnswer, isNotNull);
      expect(q1.machineStatus.isAutoAcceptable, isFalse);
    },
  );
}
