/// A versioned answer key (docs/02-data-model.md §5, Critical Rule 7).
///
/// The rule this file exists to make structurally true: **a published answer
/// key is never edited.** A correction creates a new version that supersedes
/// the old one, carrying the reason it was needed and the name of whoever
/// decided it.
///
/// Why not just fix the wrong entry in place? Because scores already exist
/// that were computed against the old key. Editing it would leave those scores
/// with no derivation — the marks would say one thing, the key another, and
/// nothing would record that the two ever disagreed. Versioning keeps the
/// history answerable: every result names the key version that produced it, so
/// "why did this child get 14?" always has an answer, even after a correction.
library;

/// The options a bubble row offers.
///
/// Fixed at four (A-D) rather than configurable: the OMR template's bubble
/// geometry is built around it, and a mismatch between a key that allows E and
/// a sheet that has nowhere to mark it is a silent scoring error.
const List<String> kAnswerOptions = <String>['A', 'B', 'C', 'D'];

/// One question's correct answer.
final class AnswerKeyEntry {
  const AnswerKeyEntry({
    required this.questionNumber,
    required this.correctOption,
    this.marks,
  });

  final int questionNumber;

  /// One of [kAnswerOptions].
  final String correctOption;

  /// Overrides the assessment's `marksPerQuestion` for this question alone.
  /// `null` means "use the assessment's value" — stored as absent rather than
  /// as a copy, so changing the assessment's default cannot leave stale
  /// per-question copies behind.
  final double? marks;

  bool get isValid => kAnswerOptions.contains(correctOption);

  Map<String, Object?> toJson() => <String, Object?>{
    'questionNumber': questionNumber,
    'correctOption': correctOption,
    if (marks != null) 'marks': marks,
  };

  static AnswerKeyEntry? tryFromJson(Map<String, Object?> json) {
    final int? questionNumber = switch (json['questionNumber']) {
      final num value => value.toInt(),
      _ => null,
    };
    final String? correctOption = json['correctOption'] as String?;
    if (questionNumber == null || correctOption == null) {
      return null;
    }
    return AnswerKeyEntry(
      questionNumber: questionNumber,
      correctOption: correctOption,
      marks: switch (json['marks']) {
        final num value => value.toDouble(),
        _ => null,
      },
    );
  }

  AnswerKeyEntry copyWith({String? correctOption, double? marks}) =>
      AnswerKeyEntry(
        questionNumber: questionNumber,
        correctOption: correctOption ?? this.correctOption,
        marks: marks ?? this.marks,
      );

  @override
  bool operator ==(Object other) =>
      other is AnswerKeyEntry &&
      other.questionNumber == questionNumber &&
      other.correctOption == correctOption &&
      other.marks == marks;

  @override
  int get hashCode => Object.hash(questionNumber, correctOption, marks);

  @override
  String toString() => 'Q$questionNumber=$correctOption';
}

/// One version of an assessment's answer key.
final class AnswerKey {
  const AnswerKey({
    required this.answerKeyId,
    required this.assessmentId,
    required this.version,
    required this.entries,
    required this.isPublished,
    required this.createdBy,
    required this.createdAt,
    this.publishedAt,
    this.supersedesVersion,
    this.changeReason,
  });

  final String answerKeyId;
  final String assessmentId;

  /// Monotonic from 1. A result records the version that scored it.
  final int version;

  /// One entry per question, ordered by question number.
  final List<AnswerKeyEntry> entries;

  /// Once true, this version is frozen. Enforced here, in
  /// `AnswerKeyPolicy`, and in `firebase/firestore.rules`, because a rule this
  /// important should not have a single point of failure.
  final bool isPublished;

  final DateTime? publishedAt;

  /// The version this one replaces, for v2 onwards.
  final int? supersedesVersion;

  /// Why the correction was needed. Required for any version above 1 — a
  /// correction with no stated reason is indistinguishable from a mistake, and
  /// requirement §14 asks for the trail.
  final String? changeReason;

  final String createdBy;
  final DateTime createdAt;

  bool get isCorrection => version > 1;

  /// Fast lookup for scoring, built once per key rather than per sheet.
  Map<int, AnswerKeyEntry> get byQuestion => <int, AnswerKeyEntry>{
    for (final AnswerKeyEntry entry in entries) entry.questionNumber: entry,
  };

  /// The correct option for [questionNumber], or `null` if the key does not
  /// cover it. Scoring treats `null` as "cannot score" rather than "wrong":
  /// a missing key entry is our failure, not the child's.
  String? optionFor(int questionNumber) =>
      byQuestion[questionNumber]?.correctOption;

  /// Question numbers that are missing or hold an option outside
  /// [kAnswerOptions], given an assessment of [totalQuestions].
  ///
  /// Returned rather than thrown so the editor can show every problem at once
  /// instead of one per save attempt.
  List<int> incompleteQuestions(int totalQuestions) {
    final Map<int, AnswerKeyEntry> lookup = byQuestion;
    return <int>[
      for (int q = 1; q <= totalQuestions; q++)
        if (lookup[q] == null || !lookup[q]!.isValid) q,
    ];
  }

  bool isCompleteFor(int totalQuestions) =>
      incompleteQuestions(totalQuestions).isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'answerKeyId': answerKeyId,
    'assessmentId': assessmentId,
    'version': version,
    'entries': entries
        .map((AnswerKeyEntry e) => e.toJson())
        .toList(growable: false),
    'isPublished': isPublished,
    'publishedAt': publishedAt?.toUtc().toIso8601String(),
    'supersedesVersion': supersedesVersion,
    'changeReason': changeReason,
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static AnswerKey? tryFromJson(Map<String, Object?> json) {
    final String? answerKeyId = json['answerKeyId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final String? createdBy = json['createdBy'] as String?;
    final int? version = switch (json['version']) {
      final num value => value.toInt(),
      _ => null,
    };
    final DateTime? createdAt = DateTime.tryParse(
      json['createdAt'] as String? ?? '',
    );
    if (answerKeyId == null ||
        assessmentId == null ||
        createdBy == null ||
        version == null ||
        createdAt == null) {
      return null;
    }
    final Object? rawEntries = json['entries'];
    final List<AnswerKeyEntry> entries = rawEntries is Iterable
        ? (rawEntries
              .whereType<Map<String, Object?>>()
              .map(AnswerKeyEntry.tryFromJson)
              .whereType<AnswerKeyEntry>()
              .toList()
            ..sort(
              (AnswerKeyEntry a, AnswerKeyEntry b) =>
                  a.questionNumber.compareTo(b.questionNumber),
            ))
        : const <AnswerKeyEntry>[];
    final Object? publishedAt = json['publishedAt'];
    return AnswerKey(
      answerKeyId: answerKeyId,
      assessmentId: assessmentId,
      version: version,
      entries: entries,
      isPublished: json['isPublished'] as bool? ?? false,
      publishedAt: publishedAt is String
          ? DateTime.tryParse(publishedAt)
          : null,
      supersedesVersion: switch (json['supersedesVersion']) {
        final num value => value.toInt(),
        _ => null,
      },
      changeReason: json['changeReason'] as String?,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }

  /// Note the absence of a way to change [version], [assessmentId] or
  /// [isPublished] back to `false`. Those are the fields that make a key
  /// identifiable and final; a caller wanting different answers wants a new
  /// version, which is what `AnswerKeyPolicy.nextVersion` builds.
  AnswerKey copyWith({
    List<AnswerKeyEntry>? entries,
    bool? isPublished,
    DateTime? publishedAt,
    String? changeReason,
  }) => AnswerKey(
    answerKeyId: answerKeyId,
    assessmentId: assessmentId,
    version: version,
    entries: entries ?? this.entries,
    isPublished: isPublished ?? this.isPublished,
    publishedAt: publishedAt ?? this.publishedAt,
    supersedesVersion: supersedesVersion,
    changeReason: changeReason ?? this.changeReason,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is AnswerKey &&
      other.answerKeyId == answerKeyId &&
      other.assessmentId == assessmentId &&
      other.version == version &&
      _listEquals(other.entries, entries) &&
      other.isPublished == isPublished &&
      other.publishedAt == publishedAt &&
      other.supersedesVersion == supersedesVersion &&
      other.changeReason == changeReason &&
      other.createdBy == createdBy &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    answerKeyId,
    assessmentId,
    version,
    Object.hashAll(entries),
    isPublished,
    publishedAt,
    supersedesVersion,
    changeReason,
    createdBy,
    createdAt,
  );

  static bool _listEquals(List<AnswerKeyEntry> a, List<AnswerKeyEntry> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'AnswerKey($assessmentId v$version, '
      '${entries.length} entries, published=$isPublished)';
}
