/// One validation decision, appended — never edited — to the log
/// (docs/02-data-model.md §6).
///
/// Separate from [OmrAnswer] on purpose: if a decision is ever revisited, the
/// first one has to stay on file rather than being overwritten by the second,
/// or the record of "someone already looked at this and said X" disappears
/// exactly when it would matter most — a dispute about who decided what.
library;

final class OmrValidationRecord {
  const OmrValidationRecord({
    required this.validationId,
    required this.omrId,
    required this.questionNumber,
    required this.machineAnswer,
    required this.machineConfidence,
    required this.chosenAnswer,
    required this.validatorUserId,
    required this.validatedAt,
    required this.deviceId,
    this.reason,
  });

  final String validationId;
  final String omrId;
  final int questionNumber;

  /// The machine's reading at the moment of this decision — copied here
  /// rather than looked up, so the log reads correctly even if something else
  /// about the answer changes later.
  final String? machineAnswer;
  final double machineConfidence;

  /// One of `kAnswerOptions`, or `Blank`/`Multiple` for the two non-answers a
  /// validator may record.
  final String chosenAnswer;

  final String validatorUserId;
  final DateTime validatedAt;
  final String deviceId;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'validationId': validationId,
    'omrId': omrId,
    'questionNumber': questionNumber,
    'machineAnswer': machineAnswer,
    'machineConfidence': machineConfidence,
    'chosenAnswer': chosenAnswer,
    'validatorUserId': validatorUserId,
    'validatedAt': validatedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'reason': reason,
  };

  static OmrValidationRecord? tryFromJson(Map<String, Object?> json) {
    final String? validationId = json['validationId'] as String?;
    final String? omrId = json['omrId'] as String?;
    final String? chosenAnswer = json['chosenAnswer'] as String?;
    final String? validatorUserId = json['validatorUserId'] as String?;
    final String? deviceId = json['deviceId'] as String?;
    final int? questionNumber = switch (json['questionNumber']) {
      final num value => value.toInt(),
      _ => null,
    };
    final DateTime? validatedAt = DateTime.tryParse(
      json['validatedAt'] as String? ?? '',
    );
    if (validationId == null ||
        omrId == null ||
        chosenAnswer == null ||
        validatorUserId == null ||
        deviceId == null ||
        questionNumber == null ||
        validatedAt == null) {
      return null;
    }
    return OmrValidationRecord(
      validationId: validationId,
      omrId: omrId,
      questionNumber: questionNumber,
      machineAnswer: json['machineAnswer'] as String?,
      machineConfidence: switch (json['machineConfidence']) {
        final num value => value.toDouble(),
        _ => 0,
      },
      chosenAnswer: chosenAnswer,
      validatorUserId: validatorUserId,
      validatedAt: validatedAt,
      deviceId: deviceId,
      reason: json['reason'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OmrValidationRecord &&
      other.validationId == validationId &&
      other.omrId == omrId &&
      other.questionNumber == questionNumber &&
      other.chosenAnswer == chosenAnswer &&
      other.validatorUserId == validatorUserId &&
      other.validatedAt == validatedAt;

  @override
  int get hashCode => Object.hash(
    validationId,
    omrId,
    questionNumber,
    chosenAnswer,
    validatorUserId,
    validatedAt,
  );

  @override
  String toString() =>
      'OmrValidationRecord($omrId Q$questionNumber -> $chosenAnswer)';
}
