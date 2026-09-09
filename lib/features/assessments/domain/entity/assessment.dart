/// An assessment: the test itself, independent of any school or sitting
/// (docs/02-data-model.md §4).
library;

/// Where an assessment is in its life.
///
/// The order matters: [AssessmentStatus.canTransitionTo] reads it, and the
/// transitions are one-way on purpose. A published assessment that could
/// quietly return to draft is a published assessment whose answer key could
/// be rewritten under the results already scored against it.
enum AssessmentStatus {
  draft('DRAFT', 'Draft'),
  published('PUBLISHED', 'Published'),
  active('ACTIVE', 'Active'),
  closed('CLOSED', 'Closed'),
  archived('ARCHIVED', 'Archived');

  const AssessmentStatus(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, AssessmentStatus> _byWireName =
      <String, AssessmentStatus>{
        for (final AssessmentStatus s in AssessmentStatus.values)
          s.wireName: s,
      };

  static AssessmentStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  /// Whether the assessment may be edited at all.
  ///
  /// Only a draft. Once published, questions and the answer key are frozen and
  /// a correction becomes a new key version instead (Critical Rule 7).
  bool get isEditable => this == AssessmentStatus.draft;

  /// Whether sessions may be conducted against it.
  bool get acceptsSubmissions =>
      this == AssessmentStatus.published || this == AssessmentStatus.active;

  /// The states this one may legally move to.
  ///
  /// Nothing returns to [draft], and [archived] is terminal. An illegal
  /// request is rejected and logged rather than applied (requirement §47) —
  /// a resumed screen or a retried sync will ask for a transition that has
  /// already happened, and that is a normal condition, not an error.
  Set<AssessmentStatus> get allowedNext => switch (this) {
    AssessmentStatus.draft => const <AssessmentStatus>{
      AssessmentStatus.published,
    },
    AssessmentStatus.published => const <AssessmentStatus>{
      AssessmentStatus.active,
      AssessmentStatus.closed,
    },
    AssessmentStatus.active => const <AssessmentStatus>{
      AssessmentStatus.closed,
    },
    AssessmentStatus.closed => const <AssessmentStatus>{
      AssessmentStatus.archived,
    },
    AssessmentStatus.archived => const <AssessmentStatus>{},
  };

  bool canTransitionTo(AssessmentStatus next) => allowedNext.contains(next);
}

final class Assessment {
  const Assessment({
    required this.assessmentId,
    required this.assessmentName,
    required this.academicYear,
    required this.grade,
    required this.subject,
    required this.totalQuestions,
    required this.marksPerQuestion,
    required this.status,
    required this.omrTemplateId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.negativeMarkPerWrongAnswer = 0,
    this.publishedAnswerKeyVersion,
    this.description,
    this.scheduledDate,
  });

  final String assessmentId;
  final String assessmentName;

  /// `"2026-27"`. Part of every storage path and every rollup key, so results
  /// from different years can never be added together by accident.
  final String academicYear;

  final String grade;
  final String subject;
  final String? description;

  final int totalQuestions;
  final double marksPerQuestion;

  /// Subtracted per wrong answer. Zero unless the programme uses negative
  /// marking; kept on the assessment rather than in app config so a change
  /// cannot silently re-score assessments that were sat under the old rule.
  final double negativeMarkPerWrongAnswer;

  final AssessmentStatus status;

  /// Which OMR sheet layout this assessment is printed on. The detection
  /// pipeline needs it to know where the bubbles are (phase 6).
  final String omrTemplateId;

  /// The answer key version currently in force, or `null` while in draft.
  ///
  /// Stored as a number rather than a document id so that "which key scored
  /// this?" is answerable from the assessment alone, and so publishing a
  /// correction is a single monotonic increment.
  final int? publishedAnswerKeyVersion;

  final DateTime? scheduledDate;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get totalMarks => totalQuestions * marksPerQuestion;

  bool get hasPublishedKey => publishedAnswerKeyVersion != null;

  /// Whether a session may be started against this assessment right now.
  ///
  /// Both halves are required: a published assessment with no key would score
  /// every sheet against nothing.
  bool get isReadyForSessions => status.acceptsSubmissions && hasPublishedKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'assessmentId': assessmentId,
    'assessmentName': assessmentName,
    'academicYear': academicYear,
    'grade': grade,
    'subject': subject,
    'description': description,
    'totalQuestions': totalQuestions,
    'marksPerQuestion': marksPerQuestion,
    'negativeMarkPerWrongAnswer': negativeMarkPerWrongAnswer,
    'status': status.wireName,
    'omrTemplateId': omrTemplateId,
    'publishedAnswerKeyVersion': publishedAnswerKeyVersion,
    'scheduledDate': scheduledDate?.toUtc().toIso8601String(),
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static Assessment? tryFromJson(Map<String, Object?> json) {
    final String? assessmentId = json['assessmentId'] as String?;
    final String? assessmentName = json['assessmentName'] as String?;
    final String? academicYear = json['academicYear'] as String?;
    final String? grade = json['grade'] as String?;
    final String? subject = json['subject'] as String?;
    final String? omrTemplateId = json['omrTemplateId'] as String?;
    final String? createdBy = json['createdBy'] as String?;
    final AssessmentStatus? status = AssessmentStatus.tryFromWireName(
      json['status'] as String?,
    );
    final int? totalQuestions = switch (json['totalQuestions']) {
      final num value => value.toInt(),
      _ => null,
    };
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    );
    if (assessmentId == null ||
        assessmentId.isEmpty ||
        assessmentName == null ||
        academicYear == null ||
        grade == null ||
        subject == null ||
        omrTemplateId == null ||
        createdBy == null ||
        status == null ||
        totalQuestions == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    final Object? scheduled = json['scheduledDate'];
    return Assessment(
      assessmentId: assessmentId,
      assessmentName: assessmentName,
      academicYear: academicYear,
      grade: grade,
      subject: subject,
      description: json['description'] as String?,
      totalQuestions: totalQuestions,
      marksPerQuestion: switch (json['marksPerQuestion']) {
        final num value => value.toDouble(),
        _ => 1,
      },
      negativeMarkPerWrongAnswer: switch (json['negativeMarkPerWrongAnswer']) {
        final num value => value.toDouble(),
        _ => 0,
      },
      status: status,
      omrTemplateId: omrTemplateId,
      publishedAnswerKeyVersion: switch (json['publishedAnswerKeyVersion']) {
        final num value => value.toInt(),
        _ => null,
      },
      scheduledDate: scheduled is String ? DateTime.tryParse(scheduled) : null,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Assessment copyWith({
    String? assessmentName,
    String? academicYear,
    String? grade,
    String? subject,
    String? description,
    int? totalQuestions,
    double? marksPerQuestion,
    double? negativeMarkPerWrongAnswer,
    AssessmentStatus? status,
    String? omrTemplateId,
    int? publishedAnswerKeyVersion,
    DateTime? scheduledDate,
    DateTime? updatedAt,
  }) => Assessment(
    assessmentId: assessmentId,
    assessmentName: assessmentName ?? this.assessmentName,
    academicYear: academicYear ?? this.academicYear,
    grade: grade ?? this.grade,
    subject: subject ?? this.subject,
    description: description ?? this.description,
    totalQuestions: totalQuestions ?? this.totalQuestions,
    marksPerQuestion: marksPerQuestion ?? this.marksPerQuestion,
    negativeMarkPerWrongAnswer:
        negativeMarkPerWrongAnswer ?? this.negativeMarkPerWrongAnswer,
    status: status ?? this.status,
    omrTemplateId: omrTemplateId ?? this.omrTemplateId,
    publishedAnswerKeyVersion:
        publishedAnswerKeyVersion ?? this.publishedAnswerKeyVersion,
    scheduledDate: scheduledDate ?? this.scheduledDate,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Assessment &&
      other.assessmentId == assessmentId &&
      other.assessmentName == assessmentName &&
      other.academicYear == academicYear &&
      other.grade == grade &&
      other.subject == subject &&
      other.description == description &&
      other.totalQuestions == totalQuestions &&
      other.marksPerQuestion == marksPerQuestion &&
      other.negativeMarkPerWrongAnswer == negativeMarkPerWrongAnswer &&
      other.status == status &&
      other.omrTemplateId == omrTemplateId &&
      other.publishedAnswerKeyVersion == publishedAnswerKeyVersion &&
      other.scheduledDate == scheduledDate &&
      other.createdBy == createdBy &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    assessmentId,
    assessmentName,
    academicYear,
    grade,
    subject,
    description,
    totalQuestions,
    marksPerQuestion,
    negativeMarkPerWrongAnswer,
    status,
    omrTemplateId,
    publishedAnswerKeyVersion,
    scheduledDate,
    createdBy,
    Object.hash(createdAt, updatedAt),
  );

  @override
  String toString() =>
      'Assessment($assessmentId, ${status.wireName}, '
      'key v$publishedAnswerKeyVersion)';
}
