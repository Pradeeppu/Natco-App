/// The answer format an assessment's questions use.
///
/// Stored per assessment rather than assumed globally (docs/02-data-model.md
/// section 4): the scorer and the answer-key editor both read the option set
/// from the assessment they are working on, so a future format needs no
/// rewrite of either.
library;

enum QuestionType {
  /// Single-answer multiple choice. The only format v1 supports.
  mcqSingle('MCQ_SINGLE', 'Multiple choice (single answer)');

  const QuestionType(this.wireName, this.displayName);

  final String wireName;
  final String displayName;

  static final Map<String, QuestionType> _byWireName = <String, QuestionType>{
    for (final QuestionType type in QuestionType.values) type.wireName: type,
  };

  static QuestionType? tryFromWireName(String? name) =>
      name == null ? null : _byWireName[name];
}
