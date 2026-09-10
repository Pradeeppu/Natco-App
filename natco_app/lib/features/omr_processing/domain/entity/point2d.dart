/// A 2D point in pixel or normalised-template coordinates, depending on
/// context.
///
/// Deliberately not `dart:ui`'s `Offset`: the whole detection/rectification
/// pipeline has to run from a plain `dart run` script (the golden-dataset
/// harness, docs/10-omr-calibration-testing.md §2) as well as inside the
/// Flutter app and `flutter test`, so nothing in `features/omr_processing`
/// may import `dart:ui` or `package:flutter`.
library;

import 'dart:math' as math;

final class Point2D {
  const Point2D(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(Point2D other) {
    final double dx = x - other.x;
    final double dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  String toString() => 'Point2D($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is Point2D && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
