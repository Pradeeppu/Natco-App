/// Firestore collection and Storage path names.
///
/// Centralised because security rules, Cloud Functions and the client all have
/// to agree on them exactly, and a mismatch shows up as a permission error
/// that looks like an authorization bug.
library;

abstract final class Collections {
  static const String users = 'users';
  static const String roles = 'roles';
  static const String states = 'states';
  static const String districts = 'districts';
  static const String clusters = 'clusters';
  static const String schools = 'schools';
  static const String students = 'students';
  static const String studentDedupe = 'student_dedupe';
  static const String studentEnrollments = 'student_enrollments';
  static const String assessments = 'assessments';
  static const String assessmentQuestions = 'assessment_questions';
  static const String answerKeys = 'answer_keys';
  static const String assessmentAssignments = 'assessment_assignments';
  static const String assessmentSessions = 'assessment_sessions';
  static const String omrSubmissions = 'omr_submissions';
  static const String omrRegistry = 'omr_registry';
  static const String omrAnswers = 'omr_answers';
  static const String omrValidations = 'omr_validations';
  static const String results = 'results';
  static const String questionAnalytics = 'question_analytics';
  static const String scopeAnalytics = 'scope_analytics';
  static const String auditLogs = 'audit_logs';
  static const String appConfig = 'app_config';
  static const String syncReceipts = 'sync_receipts';

  /// The single global configuration document.
  static const String appConfigGlobalDoc = 'global';
}

/// Local Hive box names. Prefixed so a stray box from another package cannot
/// collide.
abstract final class LocalBoxes {
  static const String session = 'natco_session';
  static const String syncQueue = 'natco_sync_queue';
  static const String schools = 'natco_schools';
  static const String students = 'natco_students';
  static const String assessments = 'natco_assessments';
  static const String answerKeys = 'natco_answer_keys';
  static const String sessions = 'natco_assessment_sessions';
  static const String omrSubmissions = 'natco_omr_submissions';
  static const String omrAnswers = 'natco_omr_answers';
  static const String auditQueue = 'natco_audit_queue';
}

/// Storage path builders.
///
/// The ancestry is encoded in the path so a Storage rule can authorize a read
/// by comparing path segments, with no database lookup
/// (docs/03-firestore-schema.md). No student name appears in any key
/// (Critical Rule 11).
abstract final class StoragePaths {
  static String omrOriginal({
    required String academicYear,
    required String assessmentId,
    required String stateId,
    required String districtId,
    required String clusterId,
    required String schoolId,
    required String date,
    required String omrId,
  }) =>
      'omr/$academicYear/$assessmentId/$stateId/$districtId/$clusterId/'
      '$schoolId/$date/OMR_$omrId.jpg';

  static String omrProcessed({
    required String academicYear,
    required String assessmentId,
    required String stateId,
    required String districtId,
    required String clusterId,
    required String schoolId,
    required String date,
    required String omrId,
  }) =>
      'omr_processed/$academicYear/$assessmentId/$stateId/$districtId/'
      '$clusterId/$schoolId/$date/OMR_${omrId}_aligned.jpg';

  static String omrBubbleCrop({
    required String academicYear,
    required String assessmentId,
    required String stateId,
    required String districtId,
    required String clusterId,
    required String schoolId,
    required String date,
    required String omrId,
    required int questionNumber,
  }) =>
      'omr_crops/$academicYear/$assessmentId/$stateId/$districtId/$clusterId/'
      '$schoolId/$date/OMR_${omrId}_q$questionNumber.jpg';

  static String report({
    required String academicYear,
    required String assessmentId,
    required String scopeLevel,
    required String scopeId,
    required String reportType,
    required String timestamp,
  }) =>
      'reports/$academicYear/$assessmentId/$scopeLevel/$scopeId/'
      '${reportType}_$timestamp.csv';
}
