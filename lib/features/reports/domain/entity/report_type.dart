/// The nine report types requirement §32 asks for. CSV only — Excel/PDF are
/// explicitly deferred (docs/08-mvp-implementation-plan.md).
library;

enum ReportType {
  studentResult(
    'STUDENT_RESULT',
    'Student result',
    'One row per student, with question-level marks',
  ),
  schoolSummary(
    'SCHOOL_SUMMARY',
    'School summary',
    'Participation, average and spread, per school',
  ),
  clusterSummary(
    'CLUSTER_SUMMARY',
    'Cluster summary',
    'School-by-school comparison within a cluster',
  ),
  districtSummary(
    'DISTRICT_SUMMARY',
    'District summary',
    'Cluster-by-cluster comparison',
  ),
  assessmentSummary(
    'ASSESSMENT_SUMMARY',
    'Assessment summary',
    'One assessment across every school in scope',
  ),
  questionAnalysis(
    'QUESTION_ANALYSIS',
    'Question analysis',
    'Correct, incorrect, blank and multiple per question',
  ),
  omrProcessing(
    'OMR_PROCESSING',
    'OMR processing',
    'Captured, processed, pending and scored, by school',
  ),
  validation(
    'VALIDATION',
    'Validation',
    'Every human decision on a flagged answer, who made it and why',
  ),
  syncFailures(
    'SYNC_FAILURES',
    'Sync failures',
    'What has not reached the server from this device, and why',
  );

  const ReportType(this.wireName, this.displayName, this.description);

  final String wireName;
  final String displayName;
  final String description;
}
