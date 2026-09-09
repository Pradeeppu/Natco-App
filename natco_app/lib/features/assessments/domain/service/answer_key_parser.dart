/// Parses a plain-text answer string into a validated `{questionNumber:
/// option}` map.
///
/// Deliberately pure and persistence-free, the same posture as
/// `StudentCsvImporter`: it only decides whether the input is *readable* —
/// the right number of positions, each a real option for this assessment.
/// Whether it may be *published* (does it belong to a real assessment, is a
/// change reason present for a correction) is the repository's job, because
/// that requires state this parser has no business knowing.
///
/// Input is one option letter per question, in question-number order,
/// separated by commas — `A,B,C,D,A` for a 5-question key — matching the
/// comma-separated convention already used for grades and mediums elsewhere
/// in this app.
library;

final class AnswerKeyParseError {
  const AnswerKeyParseError({required this.questionNumber, required this.reason});

  final int questionNumber;
  final String reason;
}

final class AnswerKeyParseResult {
  const AnswerKeyParseResult({required this.answers, required this.errors});

  final Map<int, String> answers;
  final List<AnswerKeyParseError> errors;

  bool get isValid => errors.isEmpty;
}

final class AnswerKeyParser {
  const AnswerKeyParser();

  AnswerKeyParseResult parse(
    String rawText, {
    required int questionCount,
    required List<String> options,
  }) {
    final List<String> parts = rawText.trim().isEmpty
        ? const <String>[]
        : rawText.split(',').map((String s) => s.trim()).toList(growable: false);

    final List<AnswerKeyParseError> errors = <AnswerKeyParseError>[];
    if (parts.length < questionCount) {
      errors.add(
        AnswerKeyParseError(
          questionNumber: parts.length + 1,
          reason: '${questionCount - parts.length} answer(s) missing '
              '(expected $questionCount, got ${parts.length})',
        ),
      );
    } else if (parts.length > questionCount) {
      errors.add(
        AnswerKeyParseError(
          questionNumber: questionCount + 1,
          reason: '${parts.length - questionCount} extra answer(s) provided '
              '(expected $questionCount, got ${parts.length})',
        ),
      );
    }

    final Map<String, String> byUpperCase = <String, String>{
      for (final String option in options) option.toUpperCase(): option,
    };
    final Map<int, String> answers = <int, String>{};
    final int positionsToRead = questionCount < parts.length
        ? questionCount
        : parts.length;
    for (int i = 0; i < positionsToRead; i++) {
      final int questionNumber = i + 1;
      final String token = parts[i];
      if (token.isEmpty) {
        errors.add(
          AnswerKeyParseError(
            questionNumber: questionNumber,
            reason: 'answer is missing',
          ),
        );
        continue;
      }
      final String? canonical = byUpperCase[token.toUpperCase()];
      if (canonical == null) {
        errors.add(
          AnswerKeyParseError(
            questionNumber: questionNumber,
            reason:
                '"$token" is not a valid option (expected one of '
                '${options.join(', ')})',
          ),
        );
        continue;
      }
      answers[questionNumber] = canonical;
    }

    return AnswerKeyParseResult(answers: answers, errors: errors);
  }
}
