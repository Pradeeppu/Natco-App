/// The result of analysing one captured image (docs/07-omr-pipeline.md
/// Step 2), before any sheet or marker detection runs.
///
/// Four of the six documented quality metrics are computable from the raw
/// frame alone: blur, brightness, contrast and shadow/uneven lighting. The
/// other two — resolution (pixels per template millimetre) and sheet
/// coverage — are meaningless without knowing where the sheet actually is in
/// the frame, which needs the marker detection Phase 6 builds. Rather than
/// populate them with a placeholder value nobody computed, this report
/// simply does not carry them yet; Phase 6 adds them here once it can
/// compute them for real (the same posture `Assessment.activeAnswerKeyVersion`
/// takes toward a key that has not been published yet — absent, not
/// guessed).
library;

enum ImageQualityVerdict {
  pass('PASS'),
  fail('FAIL');
  // `WARN` is part of the eventual three-way verdict (docs/02-data-model.md
  // section 6) but nothing in these four metrics defines a warn boundary
  // distinct from pass/fail — that arises once the resolution/coverage
  // checks above exist, so this phase's verdict is binary rather than a
  // guessed threshold.

  const ImageQualityVerdict(this.wireName);

  final String wireName;
}

final class ImageQualityReport {
  const ImageQualityReport({
    required this.blurScore,
    required this.brightnessScore,
    required this.contrastScore,
    required this.shadowDeviation,
    required this.verdict,
    required this.failureReasons,
  });

  /// Normalised variance-of-Laplacian, 0.0 (flat/blurred) to 1.0 (sharp).
  final double blurScore;

  /// Mean luminance of the frame, 0.0 (black) to 1.0 (white).
  final double brightnessScore;

  /// 5th-95th percentile luminance spread, 0.0 (flat/washed out) to 1.0
  /// (full range).
  final double contrastScore;

  /// Largest deviation of any 4x4-grid block's mean luminance from the
  /// frame's overall mean. 0.0 is perfectly even lighting; higher values
  /// mean part of the frame is markedly brighter or darker than the rest.
  final double shadowDeviation;

  final ImageQualityVerdict verdict;

  /// One entry per failing metric, in plain language — never a code or a
  /// bare "quality check failed" (requirement section 40).
  final List<String> failureReasons;

  Map<String, Object?> toJson() => <String, Object?>{
    'blurScore': blurScore,
    'brightnessScore': brightnessScore,
    'contrastScore': contrastScore,
    'shadowDeviation': shadowDeviation,
    'verdict': verdict.wireName,
    'failureReasons': failureReasons,
  };

  static ImageQualityReport? tryFromJson(Map<String, Object?> json) {
    final double? blurScore = (json['blurScore'] as num?)?.toDouble();
    final double? brightnessScore = (json['brightnessScore'] as num?)
        ?.toDouble();
    final double? contrastScore = (json['contrastScore'] as num?)?.toDouble();
    final double? shadowDeviation = (json['shadowDeviation'] as num?)
        ?.toDouble();
    final ImageQualityVerdict? verdict = switch (json['verdict']) {
      'PASS' => ImageQualityVerdict.pass,
      'FAIL' => ImageQualityVerdict.fail,
      _ => null,
    };
    if (blurScore == null ||
        brightnessScore == null ||
        contrastScore == null ||
        shadowDeviation == null ||
        verdict == null) {
      return null;
    }
    return ImageQualityReport(
      blurScore: blurScore,
      brightnessScore: brightnessScore,
      contrastScore: contrastScore,
      shadowDeviation: shadowDeviation,
      verdict: verdict,
      failureReasons:
          (json['failureReasons'] as List<Object?>? ?? const <Object?>[])
              .map((Object? r) => r.toString())
              .toList(growable: false),
    );
  }
}
