/// Tests for the pure answer-key text parser.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessments/domain/service/answer_key_parser.dart';

void main() {
  const AnswerKeyParser parser = AnswerKeyParser();
  const List<String> options = <String>['A', 'B', 'C', 'D'];

  test('parses a complete, valid answer string', () {
    final result = parser.parse(
      'A,B,C,D,A',
      questionCount: 5,
      options: options,
    );
    expect(result.isValid, isTrue);
    expect(result.answers, <int, String>{
      1: 'A',
      2: 'B',
      3: 'C',
      4: 'D',
      5: 'A',
    });
  });

  test('is tolerant of whitespace and lowercase input', () {
    final result = parser.parse(
      ' a , b, c ',
      questionCount: 3,
      options: options,
    );
    expect(result.isValid, isTrue);
    expect(result.answers, <int, String>{1: 'A', 2: 'B', 3: 'C'});
  });

  test('reports missing answers without throwing', () {
    final result = parser.parse('A,B', questionCount: 5, options: options);
    expect(result.isValid, isFalse);
    expect(result.answers, <int, String>{1: 'A', 2: 'B'});
    expect(
      result.errors.any((e) => e.reason.contains('3 answer(s) missing')),
      isTrue,
    );
  });

  test('reports extra answers beyond the question count', () {
    final result = parser.parse(
      'A,B,C,D,A,B',
      questionCount: 5,
      options: options,
    );
    expect(result.isValid, isFalse);
    expect(
      result.errors.any((e) => e.reason.contains('1 extra answer(s)')),
      isTrue,
    );
    // Still reads every valid position within the question count.
    expect(result.answers, <int, String>{
      1: 'A',
      2: 'B',
      3: 'C',
      4: 'D',
      5: 'A',
    });
  });

  test('flags a blank position (double comma) at its question number', () {
    final result = parser.parse('A,,C', questionCount: 3, options: options);
    expect(result.isValid, isFalse);
    expect(
      result.errors.single,
      isA<AnswerKeyParseError>()
          .having((e) => e.questionNumber, 'questionNumber', 2)
          .having((e) => e.reason, 'reason', 'answer is missing'),
    );
  });

  test('flags an option that is not in the allowed set', () {
    final result = parser.parse('A,E,C', questionCount: 3, options: options);
    expect(result.isValid, isFalse);
    final error = result.errors.single;
    expect(error.questionNumber, 2);
    expect(error.reason, contains('"E" is not a valid option'));
  });

  test('an empty string is reported as every answer missing', () {
    final result = parser.parse('', questionCount: 3, options: options);
    expect(result.isValid, isFalse);
    expect(result.answers, isEmpty);
    expect(
      result.errors.single.reason,
      contains('3 answer(s) missing (expected 3, got 0)'),
    );
  });
}
