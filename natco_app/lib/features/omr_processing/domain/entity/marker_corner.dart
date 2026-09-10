/// One of the four physical corners of a rectified sheet, in clockwise
/// order starting from top-left — the order [OmrTemplate]'s answer grid and
/// [MarkerCorner.rotationStepsTo] both assume.
library;

enum MarkerCorner {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft;

  static MarkerCorner fromWireName(String wireName) => switch (wireName) {
    'topLeft' => MarkerCorner.topLeft,
    'topRight' => MarkerCorner.topRight,
    'bottomRight' => MarkerCorner.bottomRight,
    'bottomLeft' => MarkerCorner.bottomLeft,
    _ => throw FormatException('Unknown marker corner "$wireName"'),
  };

  /// How many 90-degree **clockwise** image rotations move content
  /// currently at this corner to [target].
  ///
  /// Corners cycle clockwise as `index` 0..3 above; rotating an image `k`
  /// steps clockwise moves whatever was at corner `i - k` (mod 4) to corner
  /// `i`. Solving for `k` given a known source and target corner gives this
  /// formula — the whole basis for resolving a sheet's absolute orientation
  /// from its single asymmetric (notched) marker
  /// (docs/07-omr-pipeline.md Steps 4-5).
  int rotationStepsTo(MarkerCorner target) =>
      (target.index - index + MarkerCorner.values.length) %
      MarkerCorner.values.length;
}
