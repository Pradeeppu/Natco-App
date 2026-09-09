/// One numbered question within an [Assessment] (docs/02-data-model.md
/// section 4).
///
/// Question *text* is deliberately not stored — the paper is printed
/// separately and v1 analytics only needs per-number performance. `topic` is
/// the field that exists for grouping.
library;

final class AssessmentQuestion {
  const AssessmentQuestion({
    required this.questionId,
    required this.assessmentId,
    required this.questionNumber,
    required this.marks,
    required this.createdAt,
    required this.updatedAt,
    this.options,
    this.topic,
    this.difficulty,
  });

  final String questionId;
  final String assessmentId;
  final int questionNumber;

  /// Overrides the assessment's own option set for this question only.
  /// `null` means "use the assessment's options" — the common case.
  final List<String>? options;

  final double marks;
  final String? topic;
  final String? difficulty;
  final DateTime createdAt;
  final DateTime updatedAt;

  AssessmentQuestion copyWith({
    List<String>? options,
    bool clearOptions = false,
    double? marks,
    String? topic,
    String? difficulty,
    DateTime? updatedAt,
  }) => AssessmentQuestion(
    questionId: questionId,
    assessmentId: assessmentId,
    questionNumber: questionNumber,
    options: clearOptions ? null : (options ?? this.options),
    marks: marks ?? this.marks,
    topic: topic ?? this.topic,
    difficulty: difficulty ?? this.difficulty,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'questionId': questionId,
    'assessmentId': assessmentId,
    'questionNumber': questionNumber,
    'options': options,
    'marks': marks,
    'topic': topic,
    'difficulty': difficulty,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static AssessmentQuestion? tryFromJson(Map<String, Object?> json) {
    final String? questionId = json['questionId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final int? questionNumber = (json['questionNumber'] as num?)?.toInt();
    final double? marks = (json['marks'] as num?)?.toDouble();
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    if (questionId == null ||
        assessmentId == null ||
        questionNumber == null ||
        marks == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    final List<Object?>? rawOptions = json['options'] as List<Object?>?;
    return AssessmentQuestion(
      questionId: questionId,
      assessmentId: assessmentId,
      questionNumber: questionNumber,
      options: rawOptions?.map((Object? o) => o.toString()).toList(
        growable: false,
      ),
      marks: marks,
      topic: json['topic'] as String?,
      difficulty: json['difficulty'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
