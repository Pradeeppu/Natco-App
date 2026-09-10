/// Shared pixel-grid helper for the detection/rectification pipeline.
library;

import 'package:image/image.dart' as img;

/// Row-major grid of normalised (0.0-1.0) luminance values for [image].
///
/// The same per-pixel walk `ImageQualityAnalyzer` does for its own metrics
/// (`features/omr_capture/domain/service/image_quality_analyzer.dart`) —
/// duplicated rather than shared across features, since the two call sites
/// downscale to different working sizes for different reasons and a shared
/// helper would need to serve both without either owning it.
List<List<double>> luminanceGridOf(img.Image image) => <List<double>>[
  for (int y = 0; y < image.height; y++)
    <double>[
      for (int x = 0; x < image.width; x++)
        image.getPixel(x, y).luminanceNormalized.toDouble(),
    ],
];
