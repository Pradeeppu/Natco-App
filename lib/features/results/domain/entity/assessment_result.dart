/// One student's score for one assessment (docs/02-data-model.md §7,
/// Critical Rule 5).
///
/// Named `AssessmentResult` rather than the doc's bare "Result": this
/// codebase's `Result<T>` (`core/utils/result.dart`) is the success-or-
/// failure wrapper every repository method returns, and a second `Result`
/// class in scope would shadow it in every file that needs both.
///
/// Never mutated once written. A re-score — because a key was corrected or a
/// sheet was re-processed — writes a new row and sets [supersededBy] on the
/// old one; nothing here has a `copyWith` for [marksObtained] or any other
/// scored field, because a copy that changed one would be exactly the silent
/// score edit Critical Rule 5 forbids.
library;

final class AssessmentResult {
  const AssessmentResult({
    required this.resultId,
    required this.studentId,
    required this.assessmentId,
    required this.omrId,
    required this.sessionId,
    required this.schoolId,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.academicYear,
    required this.grade,
    required this.section,
    required this.answerKeyVersion,
    required this.totalMarks,
    required this.marksObtained,
    required this.correctCount,
    required this.incorrectCount,
    required this.blankCount,
    required this.multipleMarkCount,
    required this.scoredAt,
    required this.scoredBy,
    this.supersededBy,
  });

  final String resultId;
  final String studentId;
  final String assessmentId;
  final String omrId;
  final String sessionId;

  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;

  final String academicYear;
  final String grade;
  final String section;

  /// The key version this was scored against — the answer to "why did this
  /// child get 14?" even after a later correction changes the key
  /// (docs §4: `AnswerKey`'s own doc comment on why versioning exists).
  final int answerKeyVersion;

  final double totalMarks;
  final double marksObtained;

  final int correctCount;
  final int incorrectCount;
  final int blankCount;
  final int multipleMarkCount;

  final DateTime scoredAt;

  /// The user id that triggered scoring, or the literal string `'SYSTEM'`
  /// when it ran automatically on validation completing.
  final String scoredBy;

  /// The id of the result that replaced this one, once a re-score has run.
  /// `null` means this is the current result for this submission.
  final String? supersededBy;

  double get percentage => totalMarks <= 0 ? 0 : (marksObtained / totalMarks) * 100;

  bool get isSuperseded => supersededBy != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'resultId': resultId,
    'studentId': studentId,
    'assessmentId': assessmentId,
    'omrId': omrId,
    'sessionId': sessionId,
    'schoolId': schoolId,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'academicYear': academicYear,
    'grade': grade,
    'section': section,
    'answerKeyVersion': answerKeyVersion,
    'totalMarks': totalMarks,
    'marksObtained': marksObtained,
    'correctCount': correctCount,
    'incorrectCount': incorrectCount,
    'blankCount': blankCount,
    'multipleMarkCount': multipleMarkCount,
    'scoredAt': scoredAt.toUtc().toIso8601String(),
    'scoredBy': scoredBy,
    'supersededBy': supersededBy,
  };

  static AssessmentResult? tryFromJson(Map<String, Object?> json) {
    final String? resultId = json['resultId'] as String?;
    final String? studentId = json['studentId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? omrId = json['omrId'] as String?;
    final String? sessionId = json['sessionId'] as String?;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? academicYear = json['academicYear'] as String?;
    final String? grade = json['grade'] as String?;
    final String? section = json['section'] as String?;
    final String? scoredBy = json['scoredBy'] as String?;
    final int? answerKeyVersion = switch (json['answerKeyVersion']) {
      final num value => value.toInt(),
      _ => null,
    };
    final DateTime? scoredAt = DateTime.tryParse(
      json['scoredAt'] as String? ?? '',
    );
    if (resultId == null ||
        studentId == null ||
        assessmentId == null ||
        omrId == null ||
        sessionId == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        academicYear == null ||
        grade == null ||
        section == null ||
        scoredBy == null ||
        answerKeyVersion == null ||
        scoredAt == null) {
      return null;
    }
    double asDouble(Object? v) => switch (v) {
      final num value => value.toDouble(),
      _ => 0,
    };
    int asInt(Object? v) => switch (v) {
      final num value => value.toInt(),
      _ => 0,
    };
    return AssessmentResult(
      resultId: resultId,
      studentId: studentId,
      assessmentId: assessmentId,
      omrId: omrId,
      sessionId: sessionId,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      academicYear: academicYear,
      grade: grade,
      section: section,
      answerKeyVersion: answerKeyVersion,
      totalMarks: asDouble(json['totalMarks']),
      marksObtained: asDouble(json['marksObtained']),
      correctCount: asInt(json['correctCount']),
      incorrectCount: asInt(json['incorrectCount']),
      blankCount: asInt(json['blankCount']),
      multipleMarkCount: asInt(json['multipleMarkCount']),
      scoredAt: scoredAt,
      scoredBy: scoredBy,
      supersededBy: json['supersededBy'] as String?,
    );
  }

  /// The only mutation this entity permits: recording that a later result
  /// replaced it. Every scored field stays exactly as it was written.
  AssessmentResult copyWithSupersededBy(String resultId) => AssessmentResult(
    resultId: this.resultId,
    studentId: studentId,
    assessmentId: assessmentId,
    omrId: omrId,
    sessionId: sessionId,
    schoolId: schoolId,
    clusterId: clusterId,
    districtId: districtId,
    stateId: stateId,
    academicYear: academicYear,
    grade: grade,
    section: section,
    answerKeyVersion: answerKeyVersion,
    totalMarks: totalMarks,
    marksObtained: marksObtained,
    correctCount: correctCount,
    incorrectCount: incorrectCount,
    blankCount: blankCount,
    multipleMarkCount: multipleMarkCount,
    scoredAt: scoredAt,
    scoredBy: scoredBy,
    supersededBy: resultId,
  );

  @override
  bool operator ==(Object other) =>
      other is AssessmentResult &&
      other.resultId == resultId &&
      other.studentId == studentId &&
      other.assessmentId == assessmentId &&
      other.omrId == omrId &&
      other.answerKeyVersion == answerKeyVersion &&
      other.totalMarks == totalMarks &&
      other.marksObtained == marksObtained &&
      other.correctCount == correctCount &&
      other.incorrectCount == incorrectCount &&
      other.blankCount == blankCount &&
      other.multipleMarkCount == multipleMarkCount &&
      other.scoredAt == scoredAt &&
      other.scoredBy == scoredBy &&
      other.supersededBy == supersededBy;

  @override
  int get hashCode => Object.hash(
    resultId,
    studentId,
    assessmentId,
    omrId,
    answerKeyVersion,
    totalMarks,
    marksObtained,
    Object.hash(
      correctCount,
      incorrectCount,
      blankCount,
      multipleMarkCount,
      scoredAt,
    ),
    scoredBy,
    supersededBy,
  );

  /// Deliberately omits [studentId]: this string can reach logs (§35).
  @override
  String toString() =>
      'AssessmentResult($resultId, $assessmentId, $marksObtained/$totalMarks)';
}
