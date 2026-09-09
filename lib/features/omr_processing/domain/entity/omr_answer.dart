/// One question's machine reading, and the human decision layered over it
/// (docs/02-data-model.md §6, Critical Rule 3, requirement §20).
///
/// The field split is the whole point of this entity: [machineAnswer],
/// [machineConfidence], [machineStatus] and [optionScores] are the machine's
/// evidence and are **never rewritten** once written — `copyWith` has no way
/// to change them, `FirestoreOmrValidationDataSource`'s update only ever
/// touches the human-decision fields, and `firebase/firestore.rules` refuses
/// an update that changes any of them. [finalAnswer] is what scoring actually
/// reads, and starts out equal to the machine's answer; a validator only
/// writes to it when they disagree.
library;

/// How confidently the pipeline read one bubble row.
enum DetectionStatus {
  highConfidence('HIGH_CONFIDENCE'),
  mediumConfidence('MEDIUM_CONFIDENCE'),
  lowConfidence('LOW_CONFIDENCE'),
  blank('BLANK'),
  multipleMark('MULTIPLE_MARK'),
  unreadable('UNREADABLE');

  const DetectionStatus(this.wireName);

  final String wireName;

  static final Map<String, DetectionStatus> _byWireName = <String, DetectionStatus>{
    for (final DetectionStatus s in DetectionStatus.values) s.wireName: s,
  };

  static DetectionStatus? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];

  /// Whether this reading is trusted without a person looking at it.
  ///
  /// Only a high-confidence single mark and a genuine blank are auto-scored.
  /// Everything else — including medium confidence — waits for a human,
  /// because "probably right" is not the bar Critical Rule 3 sets.
  bool get isAutoAcceptable =>
      this == DetectionStatus.highConfidence || this == DetectionStatus.blank;
}

/// Whose decision [OmrAnswer.finalAnswer] currently reflects.
enum AnswerSource {
  machine('MACHINE'),
  humanValidation('HUMAN_VALIDATION');

  const AnswerSource(this.wireName);

  final String wireName;

  static final Map<String, AnswerSource> _byWireName = <String, AnswerSource>{
    for (final AnswerSource s in AnswerSource.values) s.wireName: s,
  };

  static AnswerSource tryFromWireName(String? name) =>
      name == null ? AnswerSource.machine : (_byWireName[name] ?? AnswerSource.machine);
}

final class OmrAnswer {
  const OmrAnswer({
    required this.omrAnswerId,
    required this.omrId,
    required this.questionNumber,
    required this.optionScores,
    required this.machineConfidence,
    required this.machineStatus,
    required this.finalAnswerSource,
    this.machineAnswer,
    this.finalAnswer,
    this.isCorrect,
    this.marks,
    this.validatedBy,
    this.validatedAt,
    this.validationReason,
    this.bubbleCropPath,
  });

  final String omrAnswerId;
  final String omrId;
  final int questionNumber;

  /// Per-option darkness, 0.0-1.0, kept as evidence even once a human decides
  /// — this is what lets a validator, and later an auditor, see *why* the
  /// machine read what it read rather than taking the confidence number on
  /// faith.
  final Map<String, double> optionScores;

  /// `null` for a genuine blank; never rewritten (see file doc).
  final String? machineAnswer;
  final double machineConfidence;
  final DetectionStatus machineStatus;

  /// What scoring reads. Starts as [machineAnswer]; a validator may replace
  /// it, and only a validator's write may change [finalAnswerSource] away
  /// from [AnswerSource.machine].
  final String? finalAnswer;
  final AnswerSource finalAnswerSource;

  /// `null` while unscored. Written by the scoring engine only — never by a
  /// validator, whose job is the *answer*, not the mark (Critical Rule 5).
  final bool? isCorrect;
  final double? marks;

  final String? validatedBy;
  final DateTime? validatedAt;
  final String? validationReason;

  /// Cropped image of just this bubble row, shown to the validator so the
  /// decision is made from the sheet rather than from a number.
  final String? bubbleCropPath;

  bool get needsValidation => !machineStatus.isAutoAcceptable;

  bool get isValidated => finalAnswerSource == AnswerSource.humanValidation;

  Map<String, Object?> toJson() => <String, Object?>{
    'omrAnswerId': omrAnswerId,
    'omrId': omrId,
    'questionNumber': questionNumber,
    'optionScores': optionScores,
    'machineAnswer': machineAnswer,
    'machineConfidence': machineConfidence,
    'machineStatus': machineStatus.wireName,
    'finalAnswer': finalAnswer,
    'finalAnswerSource': finalAnswerSource.wireName,
    'isCorrect': isCorrect,
    'marks': marks,
    'validatedBy': validatedBy,
    'validatedAt': validatedAt?.toUtc().toIso8601String(),
    'validationReason': validationReason,
    'bubbleCropPath': bubbleCropPath,
  };

  static OmrAnswer? tryFromJson(Map<String, Object?> json) {
    final String? omrAnswerId = json['omrAnswerId'] as String?;
    final String? omrId = json['omrId'] as String?;
    final DetectionStatus? machineStatus = DetectionStatus.tryFromWireName(
      json['machineStatus'] as String?,
    );
    final int? questionNumber = switch (json['questionNumber']) {
      final num value => value.toInt(),
      _ => null,
    };
    if (omrAnswerId == null ||
        omrId == null ||
        questionNumber == null ||
        machineStatus == null) {
      return null;
    }
    final Object? rawScores = json['optionScores'];
    final Object? validatedAt = json['validatedAt'];
    return OmrAnswer(
      omrAnswerId: omrAnswerId,
      omrId: omrId,
      questionNumber: questionNumber,
      optionScores: rawScores is Map
          ? rawScores.map(
              (Object? k, Object? v) => MapEntry(
                k.toString(),
                switch (v) {
                  final num value => value.toDouble(),
                  _ => 0.0,
                },
              ),
            )
          : const <String, double>{},
      machineAnswer: json['machineAnswer'] as String?,
      machineConfidence: switch (json['machineConfidence']) {
        final num value => value.toDouble(),
        _ => 0,
      },
      machineStatus: machineStatus,
      finalAnswer: json['finalAnswer'] as String?,
      finalAnswerSource: AnswerSource.tryFromWireName(
        json['finalAnswerSource'] as String?,
      ),
      isCorrect: json['isCorrect'] as bool?,
      marks: switch (json['marks']) {
        final num value => value.toDouble(),
        _ => null,
      },
      validatedBy: json['validatedBy'] as String?,
      validatedAt: validatedAt is String ? DateTime.tryParse(validatedAt) : null,
      validationReason: json['validationReason'] as String?,
      bubbleCropPath: json['bubbleCropPath'] as String?,
    );
  }

  /// Applies a human decision. Deliberately the only way [finalAnswer],
  /// [finalAnswerSource], [validatedBy], [validatedAt] or [validationReason]
  /// change — every machine-evidence field is copied forward untouched, and
  /// there is no parameter here that could touch one.
  OmrAnswer withValidation({
    required String finalAnswer,
    required String validatedBy,
    required DateTime validatedAt,
    String? validationReason,
  }) => OmrAnswer(
    omrAnswerId: omrAnswerId,
    omrId: omrId,
    questionNumber: questionNumber,
    optionScores: optionScores,
    machineAnswer: machineAnswer,
    machineConfidence: machineConfidence,
    machineStatus: machineStatus,
    finalAnswer: finalAnswer,
    finalAnswerSource: AnswerSource.humanValidation,
    isCorrect: isCorrect,
    marks: marks,
    validatedBy: validatedBy,
    validatedAt: validatedAt,
    validationReason: validationReason,
    bubbleCropPath: bubbleCropPath,
  );

  /// Applies the scoring engine's verdict. The only way [isCorrect] or
  /// [marks] change — a validator's [withValidation] never touches them, and
  /// this never touches an answer field.
  OmrAnswer withScore({required bool isCorrect, required double marks}) =>
      OmrAnswer(
        omrAnswerId: omrAnswerId,
        omrId: omrId,
        questionNumber: questionNumber,
        optionScores: optionScores,
        machineAnswer: machineAnswer,
        machineConfidence: machineConfidence,
        machineStatus: machineStatus,
        finalAnswer: finalAnswer,
        finalAnswerSource: finalAnswerSource,
        isCorrect: isCorrect,
        marks: marks,
        validatedBy: validatedBy,
        validatedAt: validatedAt,
        validationReason: validationReason,
        bubbleCropPath: bubbleCropPath,
      );

  @override
  bool operator ==(Object other) =>
      other is OmrAnswer &&
      other.omrAnswerId == omrAnswerId &&
      other.omrId == omrId &&
      other.questionNumber == questionNumber &&
      _scoresEqual(other.optionScores, optionScores) &&
      other.machineAnswer == machineAnswer &&
      other.machineConfidence == machineConfidence &&
      other.machineStatus == machineStatus &&
      other.finalAnswer == finalAnswer &&
      other.finalAnswerSource == finalAnswerSource &&
      other.isCorrect == isCorrect &&
      other.marks == marks &&
      other.validatedBy == validatedBy &&
      other.validatedAt == validatedAt &&
      other.validationReason == validationReason &&
      other.bubbleCropPath == bubbleCropPath;

  @override
  int get hashCode => Object.hash(
    omrAnswerId,
    omrId,
    questionNumber,
    Object.hashAllUnordered(optionScores.entries.map((e) => Object.hash(e.key, e.value))),
    machineAnswer,
    machineConfidence,
    machineStatus,
    finalAnswer,
    finalAnswerSource,
    isCorrect,
    Object.hash(marks, validatedBy, validatedAt, validationReason, bubbleCropPath),
  );

  static bool _scoresEqual(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<String, double> e in a.entries) {
      if (b[e.key] != e.value) {
        return false;
      }
    }
    return true;
  }

  /// Deliberately omits [bubbleCropPath]: it is a file path derived from the
  /// omrId, and Critical Rule 11 keeps identifying detail out of anything
  /// that might be logged.
  @override
  String toString() =>
      'OmrAnswer($omrId Q$questionNumber, ${machineStatus.wireName})';
}
