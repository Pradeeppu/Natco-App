/// Everything one assignment needs to run a session with no network
/// (docs/06-offline-sync-strategy.md §2): the assessment, its questions, its
/// published answer key, and the student roster for each of the assignment's
/// sections.
///
/// Downloaded once, while online (`SessionPrerequisitesDownloader`), and read
/// only from local storage after that — `AssessmentSessionsRepository.
/// startSession` never calls a network-backed repository directly.
library;

import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';

final class SessionPrerequisites {
  const SessionPrerequisites({
    required this.assignmentId,
    required this.assessment,
    required this.questions,
    required this.publishedAnswerKey,
    required this.schoolId,
    required this.clusterId,
    required this.districtId,
    required this.stateId,
    required this.grade,
    required this.studentIdsBySection,
    required this.downloadedAt,
  });

  final String assignmentId;
  final Assessment assessment;
  final List<AssessmentQuestion> questions;

  /// `null` when the assessment has no published key yet — captured as fact,
  /// not hidden, so a teacher who tries to start a session for an un-keyed
  /// assessment sees why rather than a session that silently cannot score.
  final AnswerKey? publishedAnswerKey;

  final String schoolId;
  final String clusterId;
  final String districtId;
  final String stateId;
  final String grade;

  /// Section name to the student ids enrolled in it, resolved at download
  /// time from the pre-downloaded student roster.
  final Map<String, List<String>> studentIdsBySection;

  final DateTime downloadedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'assignmentId': assignmentId,
    'assessment': assessment.toJson(),
    'questions': questions.map((q) => q.toJson()).toList(growable: false),
    'publishedAnswerKey': publishedAnswerKey?.toJson(),
    'schoolId': schoolId,
    'clusterId': clusterId,
    'districtId': districtId,
    'stateId': stateId,
    'grade': grade,
    'studentIdsBySection': studentIdsBySection,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
  };

  static SessionPrerequisites? tryFromJson(Map<String, Object?> json) {
    final String? assignmentId = json['assignmentId'] as String?;
    final Object? rawAssessment = json['assessment'];
    final Assessment? assessment = rawAssessment is Map<String, Object?>
        ? Assessment.tryFromJson(rawAssessment)
        : null;
    final String? schoolId = json['schoolId'] as String?;
    final String? clusterId = json['clusterId'] as String?;
    final String? districtId = json['districtId'] as String?;
    final String? stateId = json['stateId'] as String?;
    final String? grade = json['grade'] as String?;
    final DateTime? downloadedAt = json['downloadedAt'] is String
        ? DateTime.tryParse(json['downloadedAt']! as String)?.toUtc()
        : null;
    if (assignmentId == null ||
        assessment == null ||
        schoolId == null ||
        clusterId == null ||
        districtId == null ||
        stateId == null ||
        grade == null ||
        downloadedAt == null) {
      return null;
    }
    final List<Object?> rawQuestions =
        json['questions'] as List<Object?>? ?? const <Object?>[];
    final List<AssessmentQuestion> questions = <AssessmentQuestion>[
      for (final Object? raw in rawQuestions)
        if (raw is Map<String, Object?>) ?AssessmentQuestion.tryFromJson(raw),
    ];
    final Object? rawKey = json['publishedAnswerKey'];
    final AnswerKey? publishedAnswerKey = rawKey is Map<String, Object?>
        ? AnswerKey.tryFromJson(rawKey)
        : null;
    final Object? rawRoster = json['studentIdsBySection'];
    final Map<String, List<String>> studentIdsBySection = <String, List<String>>{
      if (rawRoster is Map)
        for (final MapEntry<Object?, Object?> entry in rawRoster.entries)
          entry.key.toString(): (entry.value as List<Object?>? ?? const <Object?>[])
              .map((Object? id) => id.toString())
              .toList(growable: false),
    };
    return SessionPrerequisites(
      assignmentId: assignmentId,
      assessment: assessment,
      questions: questions,
      publishedAnswerKey: publishedAnswerKey,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      grade: grade,
      studentIdsBySection: studentIdsBySection,
      downloadedAt: downloadedAt,
    );
  }
}
