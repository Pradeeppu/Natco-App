/// One captured sheet, from capture through to a final score
/// (docs/02-data-model.md §6).
///
/// [omrId] is what is printed on the sheet and is globally unique, enforced by
/// the `omr_registry` guard document created in the same transaction as this
/// submission (Critical Rule 7) — a second capture of the same sheet collides
/// there rather than silently creating a twin. [submissionId] is the internal
/// document identity, separate because a duplicate can be resolved as a
/// legitimate replacement, which needs its own record without reusing — or
/// freeing up — the omrId.
library;

import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';

/// Where a submission is in the pipeline (requirement §47).
///
/// Transitions are one-way and validated by [canTransitionTo] — a resumed
/// screen or a retried sync asking for a transition that already happened is
/// a normal condition and is rejected rather than silently reapplied.
enum OmrProcessingStatus {
  captured('CAPTURED', 'Captured'),
  processing('PROCESSING', 'Processing'),
  processed('PROCESSED', 'Processed'),
  needsValidation('NEEDS_VALIDATION', 'Needs validation'),
  scored('SCORED', 'Scored'),

  /// The image file is gone and the sheet cannot be re-processed. Written
  /// only by the sync reconciler when it finds a `CAPTURED`/`PROCESSING`
  /// submission with no image on disk — never silently dropped
  /// (docs/06-offline-sync-strategy.md §4).
  unreadableEvidenceMissing('UNREADABLE_EVIDENCE_MISSING', 'Evidence missing');

  const OmrProcessingStatus(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, OmrProcessingStatus> _byWireName =
      <String, OmrProcessingStatus>{
        for (final OmrProcessingStatus s in OmrProcessingStatus.values)
          s.wireName: s,
      };

  static OmrProcessingStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  Set<OmrProcessingStatus> get allowedNext => switch (this) {
    OmrProcessingStatus.captured => const <OmrProcessingStatus>{
      OmrProcessingStatus.processing,
      OmrProcessingStatus.unreadableEvidenceMissing,
    },
    OmrProcessingStatus.processing => const <OmrProcessingStatus>{
      OmrProcessingStatus.processed,
      OmrProcessingStatus.unreadableEvidenceMissing,
    },
    OmrProcessingStatus.processed => const <OmrProcessingStatus>{
      OmrProcessingStatus.needsValidation,
      OmrProcessingStatus.scored,
    },
    OmrProcessingStatus.needsValidation => const <OmrProcessingStatus>{
      OmrProcessingStatus.scored,
    },
    // Both terminal for this pipeline. A re-score after a key correction
    // supersedes the *result*, not this submission's own status.
    OmrProcessingStatus.scored => const <OmrProcessingStatus>{},
    OmrProcessingStatus.unreadableEvidenceMissing =>
        const <OmrProcessingStatus>{},
  };

  bool canTransitionTo(OmrProcessingStatus next) => allowedNext.contains(next);
}

/// Whether a submission has been through human validation
/// (docs/02-data-model.md §6).
enum ValidationStatus {
  /// Every answer was auto-acceptable; no person needs to look at it.
  notRequired('NOT_REQUIRED'),
  pending('PENDING'),
  inProgress('IN_PROGRESS'),
  completed('COMPLETED');

  const ValidationStatus(this.wireName);

  final String wireName;

  static final Map<String, ValidationStatus> _byWireName = <String, ValidationStatus>{
    for (final ValidationStatus s in ValidationStatus.values) s.wireName: s,
  };

  static ValidationStatus tryFromWireName(String? name) =>
      name == null ? ValidationStatus.notRequired : (_byWireName[name] ?? ValidationStatus.notRequired);

  /// Whether a submission at this status may be scored.
  bool get allowsScoring =>
      this == ValidationStatus.notRequired || this == ValidationStatus.completed;
}

/// How a duplicate omrId capture was resolved, once a person decides.
enum DuplicateResolutionKind {
  /// Genuinely the same sheet captured twice; the later capture is discarded.
  duplicate('DUPLICATE'),

  /// The first capture was unusable and this is a legitimate re-scan.
  replacement('REPLACEMENT'),

  /// Neither — flagged for investigation rather than guessed at.
  invalid('INVALID');

  const DuplicateResolutionKind(this.wireName);

  final String wireName;

  static final Map<String, DuplicateResolutionKind> _byWireName =
      <String, DuplicateResolutionKind>{
        for (final DuplicateResolutionKind k in DuplicateResolutionKind.values)
          k.wireName: k,
      };

  static DuplicateResolutionKind? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];
}

final class DuplicateResolution {
  const DuplicateResolution({
    required this.kind,
    required this.resolvedBy,
    required this.resolvedAt,
    required this.reason,
  });

  final DuplicateResolutionKind kind;
  final String resolvedBy;
  final DateTime resolvedAt;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wireName,
    'resolvedBy': resolvedBy,
    'resolvedAt': resolvedAt.toUtc().toIso8601String(),
    'reason': reason,
  };

  static DuplicateResolution? tryFromJson(Map<String, Object?> json) {
    final DuplicateResolutionKind? kind = DuplicateResolutionKind.tryFromWireName(
      json['kind'] as String?,
    );
    final String? resolvedBy = json['resolvedBy'] as String?;
    final DateTime? resolvedAt = DateTime.tryParse(
      json['resolvedAt'] as String? ?? '',
    );
    final String? reason = json['reason'] as String?;
    if (kind == null || resolvedBy == null || resolvedAt == null || reason == null) {
      return null;
    }
    return DuplicateResolution(
      kind: kind,
      resolvedBy: resolvedBy,
      resolvedAt: resolvedAt,
      reason: reason,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DuplicateResolution &&
      other.kind == kind &&
      other.resolvedBy == resolvedBy &&
      other.resolvedAt == resolvedAt &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(kind, resolvedBy, resolvedAt, reason);
}

final class OmrSubmission {
  const OmrSubmission({
    required this.omrId,
    required this.submissionId,
    required this.sessionId,
    required this.assessmentId,
    required this.schoolId,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.capturedBy,
    required this.capturedAt,
    required this.deviceId,
    required this.originalImagePath,
    required this.imageQuality,
    required this.processingStatus,
    required this.validationStatus,
    required this.createdAt,
    required this.updatedAt,
    this.studentId,
    this.processedImagePath,
    this.qualityOverrideBy,
    this.qualityOverrideReason,
    this.duplicateResolution,
    this.answerKeyVersion,
    this.machineScore,
    this.finalScore,
  });

  /// Printed on the sheet. Globally unique — enforced by the `omr_registry`
  /// guard document, never by this entity alone.
  final String omrId;
  final String submissionId;

  final String sessionId;
  final String assessmentId;

  /// `null` until manual or automatic identification resolves it — the sheet
  /// itself may arrive with an unreadable id bubble grid.
  final String? studentId;

  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;

  final String capturedBy;
  final DateTime capturedAt;
  final String deviceId;

  /// Local path at capture, storage path once synced. Written before any
  /// processing begins (docs/06 §1) — the evidence exists whether or not
  /// processing ever succeeds.
  final String originalImagePath;
  final String? processedImagePath;

  final ImageQualityReport imageQuality;

  /// Who forced "Use Anyway" past a failed quality gate, and why. `null` for
  /// every submission that passed cleanly.
  final String? qualityOverrideBy;
  final String? qualityOverrideReason;

  final OmrProcessingStatus processingStatus;
  final ValidationStatus validationStatus;
  final DuplicateResolution? duplicateResolution;

  /// The answer key version scoring was run against. `null` until scored.
  final int? answerKeyVersion;

  /// The on-device preview score, from machine answers only
  /// (docs/06 §2 — "Score preview: on-device, local scoring against the
  /// cached key version"). Never shown as final while [validationStatus]
  /// has not reached [ValidationStatus.completed].
  final double? machineScore;

  /// The score once every flagged answer has a human decision.
  final double? finalScore;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get wasQualityOverridden => qualityOverrideBy != null;

  bool get needsValidation => validationStatus == ValidationStatus.pending ||
      validationStatus == ValidationStatus.inProgress;

  /// Whether this submission may be scored right now.
  ///
  /// Both halves matter: [ValidationStatus.allowsScoring] is Critical Rule 3
  /// applied to a whole sheet rather than one answer, and processed-or-later
  /// keeps a sheet that has not even been read yet from being "scored" as a
  /// row of blanks.
  bool get readyForScoring =>
      validationStatus.allowsScoring &&
      (processingStatus == OmrProcessingStatus.processed ||
          processingStatus == OmrProcessingStatus.needsValidation ||
          processingStatus == OmrProcessingStatus.scored);

  Map<String, Object?> toJson() => <String, Object?>{
    'omrId': omrId,
    'submissionId': submissionId,
    'sessionId': sessionId,
    'assessmentId': assessmentId,
    'studentId': studentId,
    'schoolId': schoolId,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'capturedBy': capturedBy,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'originalImagePath': originalImagePath,
    'processedImagePath': processedImagePath,
    'imageQuality': imageQuality.toJson(),
    'qualityOverrideBy': qualityOverrideBy,
    'qualityOverrideReason': qualityOverrideReason,
    'processingStatus': processingStatus.wireName,
    'validationStatus': validationStatus.wireName,
    'duplicateResolution': duplicateResolution?.toJson(),
    'answerKeyVersion': answerKeyVersion,
    'machineScore': machineScore,
    'finalScore': finalScore,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static OmrSubmission? tryFromJson(Map<String, Object?> json) {
    final String? omrId = json['omrId'] as String?;
    final String? submissionId = json['submissionId'] as String?;
    final String? sessionId = json['sessionId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? capturedBy = json['capturedBy'] as String?;
    final String? deviceId = json['deviceId'] as String?;
    final String? originalImagePath = json['originalImagePath'] as String?;
    final OmrProcessingStatus? processingStatus =
        OmrProcessingStatus.tryFromWireName(json['processingStatus'] as String?);
    final DateTime? capturedAt = DateTime.tryParse(
      json['capturedAt'] as String? ?? '',
    );
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    );
    final Object? rawQuality = json['imageQuality'];
    final ImageQualityReport? imageQuality = rawQuality is Map<String, Object?>
        ? ImageQualityReport.tryFromJson(rawQuality)
        : null;
    if (omrId == null ||
        submissionId == null ||
        sessionId == null ||
        assessmentId == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        capturedBy == null ||
        deviceId == null ||
        originalImagePath == null ||
        processingStatus == null ||
        capturedAt == null ||
        createdAt == null ||
        updatedAt == null ||
        imageQuality == null) {
      return null;
    }
    final Object? rawDuplicate = json['duplicateResolution'];
    return OmrSubmission(
      omrId: omrId,
      submissionId: submissionId,
      sessionId: sessionId,
      assessmentId: assessmentId,
      studentId: json['studentId'] as String?,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      capturedBy: capturedBy,
      capturedAt: capturedAt,
      deviceId: deviceId,
      originalImagePath: originalImagePath,
      processedImagePath: json['processedImagePath'] as String?,
      imageQuality: imageQuality,
      qualityOverrideBy: json['qualityOverrideBy'] as String?,
      qualityOverrideReason: json['qualityOverrideReason'] as String?,
      processingStatus: processingStatus,
      validationStatus: ValidationStatus.tryFromWireName(
        json['validationStatus'] as String?,
      ),
      duplicateResolution: rawDuplicate is Map<String, Object?>
          ? DuplicateResolution.tryFromJson(rawDuplicate)
          : null,
      answerKeyVersion: switch (json['answerKeyVersion']) {
        final num value => value.toInt(),
        _ => null,
      },
      machineScore: switch (json['machineScore']) {
        final num value => value.toDouble(),
        _ => null,
      },
      finalScore: switch (json['finalScore']) {
        final num value => value.toDouble(),
        _ => null,
      },
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Note the absence of a way to change [omrId], [capturedBy], [capturedAt],
  /// [deviceId] or [originalImagePath] — provenance fixed at capture, exactly
  /// as `firebase/firestore.rules` enforces on the server.
  OmrSubmission copyWith({
    String? studentId,
    String? processedImagePath,
    String? qualityOverrideBy,
    String? qualityOverrideReason,
    OmrProcessingStatus? processingStatus,
    ValidationStatus? validationStatus,
    DuplicateResolution? duplicateResolution,
    int? answerKeyVersion,
    double? machineScore,
    double? finalScore,
    DateTime? updatedAt,
  }) => OmrSubmission(
    omrId: omrId,
    submissionId: submissionId,
    sessionId: sessionId,
    assessmentId: assessmentId,
    studentId: studentId ?? this.studentId,
    schoolId: schoolId,
    clusterId: clusterId,
    districtId: districtId,
    stateId: stateId,
    capturedBy: capturedBy,
    capturedAt: capturedAt,
    deviceId: deviceId,
    originalImagePath: originalImagePath,
    processedImagePath: processedImagePath ?? this.processedImagePath,
    imageQuality: imageQuality,
    qualityOverrideBy: qualityOverrideBy ?? this.qualityOverrideBy,
    qualityOverrideReason: qualityOverrideReason ?? this.qualityOverrideReason,
    processingStatus: processingStatus ?? this.processingStatus,
    validationStatus: validationStatus ?? this.validationStatus,
    duplicateResolution: duplicateResolution ?? this.duplicateResolution,
    answerKeyVersion: answerKeyVersion ?? this.answerKeyVersion,
    machineScore: machineScore ?? this.machineScore,
    finalScore: finalScore ?? this.finalScore,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is OmrSubmission &&
      other.omrId == omrId &&
      other.submissionId == submissionId &&
      other.sessionId == sessionId &&
      other.assessmentId == assessmentId &&
      other.studentId == studentId &&
      other.schoolId == schoolId &&
      other.capturedBy == capturedBy &&
      other.capturedAt == capturedAt &&
      other.processingStatus == processingStatus &&
      other.validationStatus == validationStatus &&
      other.answerKeyVersion == answerKeyVersion &&
      other.machineScore == machineScore &&
      other.finalScore == finalScore &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    omrId,
    submissionId,
    sessionId,
    assessmentId,
    studentId,
    schoolId,
    capturedBy,
    capturedAt,
    processingStatus,
    validationStatus,
    answerKeyVersion,
    Object.hash(machineScore, finalScore, updatedAt),
  );

  /// Deliberately omits [studentId]: this string can reach logs, and which
  /// child a sheet belongs to is exactly the personal detail requirement §35
  /// keeps out of them.
  @override
  String toString() => 'OmrSubmission($omrId, ${processingStatus.wireName})';
}
