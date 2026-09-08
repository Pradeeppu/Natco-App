/// Configurable OMR scanner thresholds.
///
/// These are the numbers that decide whether a bubble is filled, whether an
/// answer is ambiguous, and whether a sheet goes to a human. Requirement
/// section 19 is explicit that they must be calibratable, so they live in
/// configuration — shipped as defaults, then overridden from
/// `app_config/global` — and never as constants inside the classifier.
///
/// The defaults below are **starting points for calibration, not validated
/// values**. No accuracy claim attaches to them; see
/// docs/10-omr-calibration-testing.md.
library;

import 'dart:math' as math;

/// Image-quality gate thresholds.
final class ImageQualityThresholds {
  const ImageQualityThresholds({
    this.minBlurScore = 0.35,
    this.minBrightness = 0.25,
    this.maxBrightness = 0.92,
    this.minContrast = 0.30,
    this.maxShadowDeviation = 0.28,
    this.minPixelsPerMillimetre = 4.0,
    this.minSheetCoverage = 0.45,
    this.maxRotationDegrees = 20.0,
    this.maxPerspectiveSkew = 0.25,
  });

  /// Normalised variance-of-Laplacian floor. Below this, the photo is blurred.
  final double minBlurScore;

  /// Mean luminance bounds for the sheet region, 0.0-1.0.
  final double minBrightness;
  final double maxBrightness;

  /// 5th-95th percentile luminance spread floor.
  final double minContrast;

  /// Largest acceptable deviation of block means across a 4x4 grid. Catches a
  /// sheet lit from one side, which a global brightness check passes.
  final double maxShadowDeviation;

  /// Resolution floor, expressed against the template's physical size rather
  /// than in absolute pixels, so it holds for any sheet size.
  final double minPixelsPerMillimetre;

  /// Minimum fraction of the frame the sheet must occupy.
  final double minSheetCoverage;

  /// Rotation the pipeline will correct; beyond this the user is asked to
  /// retake, because extreme angles lose bubble resolution.
  final double maxRotationDegrees;

  /// Normalised measure of how non-rectangular the detected quad is.
  final double maxPerspectiveSkew;

  ImageQualityThresholds copyWith({
    double? minBlurScore,
    double? minBrightness,
    double? maxBrightness,
    double? minContrast,
    double? maxShadowDeviation,
    double? minPixelsPerMillimetre,
    double? minSheetCoverage,
    double? maxRotationDegrees,
    double? maxPerspectiveSkew,
  }) => ImageQualityThresholds(
    minBlurScore: minBlurScore ?? this.minBlurScore,
    minBrightness: minBrightness ?? this.minBrightness,
    maxBrightness: maxBrightness ?? this.maxBrightness,
    minContrast: minContrast ?? this.minContrast,
    maxShadowDeviation: maxShadowDeviation ?? this.maxShadowDeviation,
    minPixelsPerMillimetre:
        minPixelsPerMillimetre ?? this.minPixelsPerMillimetre,
    minSheetCoverage: minSheetCoverage ?? this.minSheetCoverage,
    maxRotationDegrees: maxRotationDegrees ?? this.maxRotationDegrees,
    maxPerspectiveSkew: maxPerspectiveSkew ?? this.maxPerspectiveSkew,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'minBlurScore': minBlurScore,
    'minBrightness': minBrightness,
    'maxBrightness': maxBrightness,
    'minContrast': minContrast,
    'maxShadowDeviation': maxShadowDeviation,
    'minPixelsPerMillimetre': minPixelsPerMillimetre,
    'minSheetCoverage': minSheetCoverage,
    'maxRotationDegrees': maxRotationDegrees,
    'maxPerspectiveSkew': maxPerspectiveSkew,
  };

  static ImageQualityThresholds fromJson(Map<String, Object?> json) {
    const ImageQualityThresholds defaults = ImageQualityThresholds();
    double read(String key, double fallback) {
      final Object? value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return ImageQualityThresholds(
      minBlurScore: read('minBlurScore', defaults.minBlurScore),
      minBrightness: read('minBrightness', defaults.minBrightness),
      maxBrightness: read('maxBrightness', defaults.maxBrightness),
      minContrast: read('minContrast', defaults.minContrast),
      maxShadowDeviation: read(
        'maxShadowDeviation',
        defaults.maxShadowDeviation,
      ),
      minPixelsPerMillimetre: read(
        'minPixelsPerMillimetre',
        defaults.minPixelsPerMillimetre,
      ),
      minSheetCoverage: read('minSheetCoverage', defaults.minSheetCoverage),
      maxRotationDegrees: read(
        'maxRotationDegrees',
        defaults.maxRotationDegrees,
      ),
      maxPerspectiveSkew: read(
        'maxPerspectiveSkew',
        defaults.maxPerspectiveSkew,
      ),
    );
  }
}

/// Bubble-fill and answer-classification thresholds.
final class BubbleThresholds {
  const BubbleThresholds({
    this.blankThreshold = 0.25,
    this.filledThreshold = 0.45,
    this.multipleMarkThreshold = 0.55,
    this.clearMargin = 0.30,
    this.ambiguousMargin = 0.15,
    this.meanInkWeight = 0.5,
    this.coverageWeight = 0.5,
    this.samplingDiameterRatio = 0.80,
  });

  /// Top score below this: the question is [BLANK].
  final double blankThreshold;

  /// Top score must reach this to be a confident fill.
  final double filledThreshold;

  /// Second-highest score at or above this: MULTIPLE_MARK.
  final double multipleMarkThreshold;

  /// Gap between the top two scores that makes a reading unambiguous.
  final double clearMargin;

  /// Gap below which a reading is LOW_CONFIDENCE and must go to a human.
  final double ambiguousMargin;

  /// Weights combining the two fill measures. They fail differently:
  /// mean ink catches a faint but complete pencil fill, coverage catches a
  /// dark but partial tick.
  final double meanInkWeight;
  final double coverageWeight;

  /// Fraction of the nominal bubble diameter that is sampled, so the printed
  /// ring around the bubble is not counted as ink.
  final double samplingDiameterRatio;

  /// Whether the weights form a convex combination, as the fill formula
  /// assumes. Checked at load time rather than trusted.
  bool get hasValidWeights =>
      (meanInkWeight + coverageWeight - 1.0).abs() < 1e-6;

  /// Whether the thresholds are internally consistent.
  ///
  /// An inverted set (`blank > filled`, say) would classify everything as one
  /// label and could easily go unnoticed, so a bad configuration is rejected
  /// at load rather than applied.
  bool get isConsistent =>
      blankThreshold > 0 &&
      blankThreshold < filledThreshold &&
      filledThreshold <= multipleMarkThreshold &&
      multipleMarkThreshold <= 1.0 &&
      ambiguousMargin > 0 &&
      ambiguousMargin < clearMargin &&
      clearMargin <= 1.0 &&
      hasValidWeights &&
      samplingDiameterRatio > 0 &&
      samplingDiameterRatio <= 1.0;

  BubbleThresholds copyWith({
    double? blankThreshold,
    double? filledThreshold,
    double? multipleMarkThreshold,
    double? clearMargin,
    double? ambiguousMargin,
    double? meanInkWeight,
    double? coverageWeight,
    double? samplingDiameterRatio,
  }) => BubbleThresholds(
    blankThreshold: blankThreshold ?? this.blankThreshold,
    filledThreshold: filledThreshold ?? this.filledThreshold,
    multipleMarkThreshold: multipleMarkThreshold ?? this.multipleMarkThreshold,
    clearMargin: clearMargin ?? this.clearMargin,
    ambiguousMargin: ambiguousMargin ?? this.ambiguousMargin,
    meanInkWeight: meanInkWeight ?? this.meanInkWeight,
    coverageWeight: coverageWeight ?? this.coverageWeight,
    samplingDiameterRatio: samplingDiameterRatio ?? this.samplingDiameterRatio,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'blankThreshold': blankThreshold,
    'filledThreshold': filledThreshold,
    'multipleMarkThreshold': multipleMarkThreshold,
    'clearMargin': clearMargin,
    'ambiguousMargin': ambiguousMargin,
    'meanInkWeight': meanInkWeight,
    'coverageWeight': coverageWeight,
    'samplingDiameterRatio': samplingDiameterRatio,
  };

  static BubbleThresholds fromJson(Map<String, Object?> json) {
    const BubbleThresholds defaults = BubbleThresholds();
    double read(String key, double fallback) {
      final Object? value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return BubbleThresholds(
      blankThreshold: read('blankThreshold', defaults.blankThreshold),
      filledThreshold: read('filledThreshold', defaults.filledThreshold),
      multipleMarkThreshold: read(
        'multipleMarkThreshold',
        defaults.multipleMarkThreshold,
      ),
      clearMargin: read('clearMargin', defaults.clearMargin),
      ambiguousMargin: read('ambiguousMargin', defaults.ambiguousMargin),
      meanInkWeight: read('meanInkWeight', defaults.meanInkWeight),
      coverageWeight: read('coverageWeight', defaults.coverageWeight),
      samplingDiameterRatio: read(
        'samplingDiameterRatio',
        defaults.samplingDiameterRatio,
      ),
    );
  }
}

/// Weights for the confidence score.
final class ConfidenceWeights {
  const ConfidenceWeights({
    this.marginWeight = 0.55,
    this.fillWeight = 0.30,
    this.imageQualityWeight = 0.15,
    this.mediumConfidenceFloor = 0.60,
    this.highConfidenceFloor = 0.80,
  });

  final double marginWeight;
  final double fillWeight;

  /// Image quality is folded into confidence deliberately: an identical bubble
  /// pattern read off a shadowed, blurry photo deserves less confidence than
  /// one read off a clean scan.
  final double imageQualityWeight;

  /// Confidence at or above this is at least MEDIUM.
  final double mediumConfidenceFloor;

  /// Confidence at or above this is HIGH.
  final double highConfidenceFloor;

  bool get hasValidWeights =>
      (marginWeight + fillWeight + imageQualityWeight - 1.0).abs() < 1e-6;

  bool get isConsistent =>
      hasValidWeights &&
      mediumConfidenceFloor > 0 &&
      mediumConfidenceFloor < highConfidenceFloor &&
      highConfidenceFloor <= 1.0;

  /// Combines the three signals into a 0.0-1.0 confidence.
  double score({
    required double topScore,
    required double runnerUpScore,
    required double imageQualityScore,
  }) {
    final double normalisedMargin =
        (topScore - runnerUpScore) / math.max(topScore, 1e-6);
    final double raw =
        marginWeight * normalisedMargin.clamp(0.0, 1.0) +
        fillWeight * topScore.clamp(0.0, 1.0) +
        imageQualityWeight * imageQualityScore.clamp(0.0, 1.0);
    return raw.clamp(0.0, 1.0);
  }

  ConfidenceWeights copyWith({
    double? marginWeight,
    double? fillWeight,
    double? imageQualityWeight,
    double? mediumConfidenceFloor,
    double? highConfidenceFloor,
  }) => ConfidenceWeights(
    marginWeight: marginWeight ?? this.marginWeight,
    fillWeight: fillWeight ?? this.fillWeight,
    imageQualityWeight: imageQualityWeight ?? this.imageQualityWeight,
    mediumConfidenceFloor: mediumConfidenceFloor ?? this.mediumConfidenceFloor,
    highConfidenceFloor: highConfidenceFloor ?? this.highConfidenceFloor,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'marginWeight': marginWeight,
    'fillWeight': fillWeight,
    'imageQualityWeight': imageQualityWeight,
    'mediumConfidenceFloor': mediumConfidenceFloor,
    'highConfidenceFloor': highConfidenceFloor,
  };

  static ConfidenceWeights fromJson(Map<String, Object?> json) {
    const ConfidenceWeights defaults = ConfidenceWeights();
    double read(String key, double fallback) {
      final Object? value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return ConfidenceWeights(
      marginWeight: read('marginWeight', defaults.marginWeight),
      fillWeight: read('fillWeight', defaults.fillWeight),
      imageQualityWeight: read(
        'imageQualityWeight',
        defaults.imageQualityWeight,
      ),
      mediumConfidenceFloor: read(
        'mediumConfidenceFloor',
        defaults.mediumConfidenceFloor,
      ),
      highConfidenceFloor: read(
        'highConfidenceFloor',
        defaults.highConfidenceFloor,
      ),
    );
  }
}

/// The full calibratable threshold set, versioned so a report can name the
/// configuration that produced it.
final class ScannerThresholds {
  const ScannerThresholds({
    this.version = 1,
    this.imageQuality = const ImageQualityThresholds(),
    this.bubbles = const BubbleThresholds(),
    this.confidence = const ConfidenceWeights(),
    this.requireValidationForMediumConfidence = false,
  });

  final int version;
  final ImageQualityThresholds imageQuality;
  final BubbleThresholds bubbles;
  final ConfidenceWeights confidence;

  /// Whether MEDIUM_CONFIDENCE answers must also be seen by a human.
  ///
  /// Left off by default and configurable because whether medium-confidence
  /// answers need human eyes is an empirical question for the calibration
  /// dataset, not one to guess (docs/07-omr-pipeline.md, step 11).
  final bool requireValidationForMediumConfidence;

  /// Whether this threshold set is safe to apply.
  bool get isConsistent => bubbles.isConsistent && confidence.isConsistent;

  ScannerThresholds copyWith({
    int? version,
    ImageQualityThresholds? imageQuality,
    BubbleThresholds? bubbles,
    ConfidenceWeights? confidence,
    bool? requireValidationForMediumConfidence,
  }) => ScannerThresholds(
    version: version ?? this.version,
    imageQuality: imageQuality ?? this.imageQuality,
    bubbles: bubbles ?? this.bubbles,
    confidence: confidence ?? this.confidence,
    requireValidationForMediumConfidence:
        requireValidationForMediumConfidence ??
        this.requireValidationForMediumConfidence,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'imageQuality': imageQuality.toJson(),
    'bubbles': bubbles.toJson(),
    'confidence': confidence.toJson(),
    'requireValidationForMediumConfidence':
        requireValidationForMediumConfidence,
  };

  /// Reads a threshold set from configuration.
  ///
  /// Returns `null` when the result would be inconsistent. A caller that gets
  /// `null` keeps the previous set and logs the rejection: applying an
  /// inverted threshold set would silently reclassify every answer, which is
  /// far worse than ignoring a bad config document.
  static ScannerThresholds? tryFromJson(Map<String, Object?> json) {
    final Object? version = json['version'];
    final Object? imageQuality = json['imageQuality'];
    final Object? bubbles = json['bubbles'];
    final Object? confidence = json['confidence'];
    final ScannerThresholds candidate = ScannerThresholds(
      version: version is num ? version.toInt() : 1,
      imageQuality: imageQuality is Map<String, Object?>
          ? ImageQualityThresholds.fromJson(imageQuality)
          : const ImageQualityThresholds(),
      bubbles: bubbles is Map<String, Object?>
          ? BubbleThresholds.fromJson(bubbles)
          : const BubbleThresholds(),
      confidence: confidence is Map<String, Object?>
          ? ConfidenceWeights.fromJson(confidence)
          : const ConfidenceWeights(),
      requireValidationForMediumConfidence:
          json['requireValidationForMediumConfidence'] == true,
    );
    return candidate.isConsistent ? candidate : null;
  }
}
