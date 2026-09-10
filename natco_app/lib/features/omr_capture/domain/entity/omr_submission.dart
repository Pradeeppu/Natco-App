/// One captured OMR sheet (docs/02-data-model.md section 6).
///
/// Scoped to what Phase 5 (capture) actually produces. `processedImagePath`,
/// `duplicateResolution`, `answerKeyVersion`, `machineScore` and
/// `finalScore` are documented fields of the eventual submission but are
/// absent here rather than present-and-null: nothing in this phase computes
/// a rectified image, checks a duplicate registry, or scores anything, and a
/// field with no real value behind it is exactly the kind of invented data
/// this product must never show (Critical Rules 3 and 14). Phase 6 adds the
/// first three once marker detection and ID decode exist; Phase 8 adds the
/// scores once scoring exists — the same pattern
/// `Assessment.activeAnswerKeyVersion` followed by not existing until
/// Phase 3 had an answer key to publish.
library;

import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/quality_override.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';

final class OmrSubmission {
  const OmrSubmission({
    required this.submissionId,
    required this.omrId,
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
    this.qualityOverride,
  });

  final String submissionId;

  /// The physical id printed on the sheet. Manually entered in this phase —
  /// there is no bubble-grid decode until Phase 6, so every submission's id
  /// comes from an operator reading the printed digits, the same fallback
  /// path the eventual auto-decode uses when it cannot read the grid
  /// (docs/07-omr-pipeline.md Step 7: `omrIdSource = MANUAL`).
  final String omrId;

  final String sessionId;
  final String assessmentId;

  /// Nullable per the documented shape: an id is not always immediately
  /// resolvable to a student. This phase's capture flow always sets it
  /// (picked from the session roster), but the field stays optional so a
  /// later phase's auto-identification is not forced to invent a value
  /// where none exists.
  final String? studentId;

  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;

  final String capturedBy;
  final DateTime capturedAt;
  final String deviceId;

  /// Local path the JPEG was durably written to, before quality analysis or
  /// any other processing ran (docs/06-offline-sync-strategy.md §1).
  final String originalImagePath;

  final ImageQualityReport imageQuality;
  final QualityOverride? qualityOverride;

  final OmrProcessingStatus processingStatus;
  final ValidationStatus validationStatus;

  final DateTime createdAt;
  final DateTime updatedAt;

  OmrSubmission copyWith({
    String? studentId,
    QualityOverride? qualityOverride,
    OmrProcessingStatus? processingStatus,
    ValidationStatus? validationStatus,
    DateTime? updatedAt,
  }) => OmrSubmission(
    submissionId: submissionId,
    omrId: omrId,
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
    imageQuality: imageQuality,
    qualityOverride: qualityOverride ?? this.qualityOverride,
    processingStatus: processingStatus ?? this.processingStatus,
    validationStatus: validationStatus ?? this.validationStatus,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'submissionId': submissionId,
    'omrId': omrId,
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
    'imageQuality': imageQuality.toJson(),
    'qualityOverride': qualityOverride?.toJson(),
    'processingStatus': processingStatus.wireName,
    'validationStatus': validationStatus.wireName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static OmrSubmission? tryFromJson(Map<String, Object?> json) {
    final String? submissionId = json['submissionId'] as String?;
    final String? omrId = json['omrId'] as String?;
    final String? sessionId = json['sessionId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? capturedBy = json['capturedBy'] as String?;
    final String? deviceId = json['deviceId'] as String?;
    final String? originalImagePath = json['originalImagePath'] as String?;
    final Object? rawQuality = json['imageQuality'];
    final ImageQualityReport? imageQuality = rawQuality is Map<String, Object?>
        ? ImageQualityReport.tryFromJson(rawQuality)
        : null;
    final OmrProcessingStatus? processingStatus =
        OmrProcessingStatus.tryFromWireName(json['processingStatus'] as String?);
    final ValidationStatus? validationStatus = ValidationStatus.tryFromWireName(
      json['validationStatus'] as String?,
    );
    final DateTime? capturedAt = _parseUtc(json['capturedAt']);
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    if (submissionId == null ||
        omrId == null ||
        sessionId == null ||
        assessmentId == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        capturedBy == null ||
        deviceId == null ||
        originalImagePath == null ||
        imageQuality == null ||
        processingStatus == null ||
        validationStatus == null ||
        capturedAt == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    final Object? rawOverride = json['qualityOverride'];
    return OmrSubmission(
      submissionId: submissionId,
      omrId: omrId,
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
      imageQuality: imageQuality,
      qualityOverride: rawOverride is Map<String, Object?>
          ? QualityOverride.tryFromJson(rawOverride)
          : null,
      processingStatus: processingStatus,
      validationStatus: validationStatus,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
