/// Records who forced a `FAIL`-verdict image through the quality gate, and
/// why (docs/07-omr-pipeline.md: `*` "Use Anyway" requires
/// `overrideQualityGate`). Kept as its own value object, embedded on the
/// submission, so the override is inseparable from the record it applied
/// to — the same posture as `OmrValidation` being append-only evidence
/// rather than a bare boolean.
library;

final class QualityOverride {
  const QualityOverride({
    required this.overriddenBy,
    required this.reason,
    required this.overriddenAt,
  });

  final String overriddenBy;
  final String reason;
  final DateTime overriddenAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'overriddenBy': overriddenBy,
    'reason': reason,
    'overriddenAt': overriddenAt.toUtc().toIso8601String(),
  };

  static QualityOverride? tryFromJson(Map<String, Object?> json) {
    final String? overriddenBy = json['overriddenBy'] as String?;
    final String? reason = json['reason'] as String?;
    final Object? rawAt = json['overriddenAt'];
    final DateTime? overriddenAt = rawAt is String
        ? DateTime.tryParse(rawAt)?.toUtc()
        : null;
    if (overriddenBy == null || reason == null || overriddenAt == null) {
      return null;
    }
    return QualityOverride(
      overriddenBy: overriddenBy,
      reason: reason,
      overriddenAt: overriddenAt,
    );
  }
}
