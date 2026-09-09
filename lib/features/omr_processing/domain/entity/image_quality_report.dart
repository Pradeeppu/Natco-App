/// The image-quality gate's verdict on one captured sheet
/// (docs/02-data-model.md §6, requirement §17).
///
/// Recorded on the submission rather than discarded once the gate passes: a
/// sheet that scraped through with a rotation of 11 degrees and one marker
/// found late is useful evidence when someone later asks why a question
/// misread, even though it was accepted at the time.
library;

enum QualityVerdict {
  pass('PASS'),
  warn('WARN'),
  fail('FAIL');

  const QualityVerdict(this.wireName);

  final String wireName;

  static final Map<String, QualityVerdict> _byWireName = <String, QualityVerdict>{
    for (final QualityVerdict v in QualityVerdict.values) v.wireName: v,
  };

  static QualityVerdict? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];
}

final class ImageQualityReport {
  const ImageQualityReport({
    required this.blurScore,
    required this.brightnessScore,
    required this.contrastScore,
    required this.resolutionPx,
    required this.sheetDetected,
    required this.markersDetected,
    required this.rotationDegrees,
    required this.perspectiveSkew,
    required this.verdict,
    this.failureReasons = const <String>[],
  });

  /// 0.0 (unusably blurred) to 1.0 (sharp).
  final double blurScore;

  /// 0.0 (unusably dark or blown out) to 1.0 (well exposed).
  final double brightnessScore;

  final double contrastScore;
  final int resolutionPx;
  final bool sheetDetected;

  /// 0-4. All four registration markers found is what makes a homography
  /// solvable; fewer is not "a worse read", it is "no read".
  final int markersDetected;

  final double rotationDegrees;
  final double perspectiveSkew;
  final QualityVerdict verdict;

  /// Plain-language reasons, shown verbatim on the capture screen — each
  /// quality failure needs its own message rather than one generic "retake"
  /// (docs/08-mvp-implementation-plan.md, phase 5 exit criteria).
  final List<String> failureReasons;

  bool get canProcess => verdict != QualityVerdict.fail;

  Map<String, Object?> toJson() => <String, Object?>{
    'blurScore': blurScore,
    'brightnessScore': brightnessScore,
    'contrastScore': contrastScore,
    'resolutionPx': resolutionPx,
    'sheetDetected': sheetDetected,
    'markersDetected': markersDetected,
    'rotationDegrees': rotationDegrees,
    'perspectiveSkew': perspectiveSkew,
    'verdict': verdict.wireName,
    'failureReasons': failureReasons,
  };

  static ImageQualityReport? tryFromJson(Map<String, Object?> json) {
    final QualityVerdict? verdict = QualityVerdict.tryFromWireName(
      json['verdict'] as String?,
    );
    if (verdict == null) {
      return null;
    }
    double asDouble(Object? v) => switch (v) {
      final num value => value.toDouble(),
      _ => 0,
    };
    final Object? rawReasons = json['failureReasons'];
    return ImageQualityReport(
      blurScore: asDouble(json['blurScore']),
      brightnessScore: asDouble(json['brightnessScore']),
      contrastScore: asDouble(json['contrastScore']),
      resolutionPx: switch (json['resolutionPx']) {
        final num value => value.toInt(),
        _ => 0,
      },
      sheetDetected: json['sheetDetected'] as bool? ?? false,
      markersDetected: switch (json['markersDetected']) {
        final num value => value.toInt(),
        _ => 0,
      },
      rotationDegrees: asDouble(json['rotationDegrees']),
      perspectiveSkew: asDouble(json['perspectiveSkew']),
      verdict: verdict,
      failureReasons: rawReasons is Iterable
          ? rawReasons.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ImageQualityReport &&
      other.blurScore == blurScore &&
      other.brightnessScore == brightnessScore &&
      other.contrastScore == contrastScore &&
      other.resolutionPx == resolutionPx &&
      other.sheetDetected == sheetDetected &&
      other.markersDetected == markersDetected &&
      other.rotationDegrees == rotationDegrees &&
      other.perspectiveSkew == perspectiveSkew &&
      other.verdict == verdict &&
      _listEquals(other.failureReasons, failureReasons);

  @override
  int get hashCode => Object.hash(
    blurScore,
    brightnessScore,
    contrastScore,
    resolutionPx,
    sheetDetected,
    markersDetected,
    rotationDegrees,
    perspectiveSkew,
    verdict,
    Object.hashAll(failureReasons),
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'ImageQualityReport(${verdict.wireName}, markers=$markersDetected/4)';
}
