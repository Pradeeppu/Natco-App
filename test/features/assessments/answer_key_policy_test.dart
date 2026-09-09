/// Tests for [AnswerKeyPolicy] — Critical Rule 7 in code.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/service/answer_key_policy.dart';

AnswerKey _key({
  int version = 1,
  bool isPublished = false,
  List<AnswerKeyEntry> entries = const <AnswerKeyEntry>[],
  int? supersedesVersion,
  String? changeReason,
}) => AnswerKey(
  answerKeyId: 'ak_1',
  assessmentId: 'as_1',
  version: version,
  entries: entries,
  isPublished: isPublished,
  supersedesVersion: supersedesVersion,
  changeReason: changeReason,
  createdBy: 'u1',
  createdAt: DateTime.utc(2026, 1, 1),
);

Assessment _assessment({int totalQuestions = 3}) => Assessment(
  assessmentId: 'as_1',
  assessmentName: 'Test',
  academicYear: '2026-27',
  grade: '5',
  subject: 'Maths',
  totalQuestions: totalQuestions,
  marksPerQuestion: 1,
  status: AssessmentStatus.draft,
  omrTemplateId: 'tpl_1',
  createdBy: 'u1',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('checkEditable', () {
    test('a draft is editable', () {
      expect(AnswerKeyPolicy.checkEditable(_key()), isNull);
    });

    test('a published key is never editable', () {
      final failure = AnswerKeyPolicy.checkEditable(_key(isPublished: true));
      expect(failure, isNotNull);
      expect(failure!.userMessage, contains('cannot be changed'));
    });
  });

  group('checkPublishable', () {
    test('refuses an incomplete key', () {
      final key = _key(
        entries: const <AnswerKeyEntry>[
          AnswerKeyEntry(questionNumber: 1, correctOption: 'A'),
        ],
      );
      final failure = AnswerKeyPolicy.checkPublishable(
        key: key,
        assessment: _assessment(),
      );
      expect(failure, isNotNull);
      expect(failure!.userMessage, contains('not finished'));
    });

    test('refuses a correction with no reason', () {
      final key = _key(
        version: 2,
        supersedesVersion: 1,
        entries: <AnswerKeyEntry>[
          for (int q = 1; q <= 3; q++)
            AnswerKeyEntry(questionNumber: q, correctOption: 'A'),
        ],
      );
      final failure = AnswerKeyPolicy.checkPublishable(
        key: key,
        assessment: _assessment(),
      );
      expect(failure, isNotNull);
      expect(failure!.userMessage, contains('Say why'));
    });

    test('refuses a key that is already published', () {
      final key = _key(
        isPublished: true,
        entries: <AnswerKeyEntry>[
          for (int q = 1; q <= 3; q++)
            AnswerKeyEntry(questionNumber: q, correctOption: 'A'),
        ],
      );
      expect(
        AnswerKeyPolicy.checkPublishable(key: key, assessment: _assessment()),
        isNotNull,
      );
    });

    test('allows a complete v1 with no reason required', () {
      final key = _key(
        entries: <AnswerKeyEntry>[
          for (int q = 1; q <= 3; q++)
            AnswerKeyEntry(questionNumber: q, correctOption: 'A'),
        ],
      );
      expect(
        AnswerKeyPolicy.checkPublishable(key: key, assessment: _assessment()),
        isNull,
      );
    });

    test('allows a complete correction with a reason', () {
      final key = _key(
        version: 2,
        supersedesVersion: 1,
        changeReason: 'Q2 was mis-keyed.',
        entries: <AnswerKeyEntry>[
          for (int q = 1; q <= 3; q++)
            AnswerKeyEntry(questionNumber: q, correctOption: 'A'),
        ],
      );
      expect(
        AnswerKeyPolicy.checkPublishable(key: key, assessment: _assessment()),
        isNull,
      );
    });
  });

  group('nextVersion', () {
    test('carries answers forward and increments the version', () {
      final published = _key(
        isPublished: true,
        entries: const <AnswerKeyEntry>[
          AnswerKeyEntry(questionNumber: 1, correctOption: 'A'),
          AnswerKeyEntry(questionNumber: 2, correctOption: 'B'),
        ],
      );
      final next = AnswerKeyPolicy.nextVersion(
        published,
        answerKeyId: 'ak_2',
        changeReason: 'Q2 correction',
        createdBy: 'u2',
        createdAt: DateTime.utc(2026, 2, 1),
      );

      expect(next.version, 2);
      expect(next.supersedesVersion, 1);
      expect(next.isPublished, isFalse);
      expect(next.entries, published.entries);
      expect(next.changeReason, 'Q2 correction');
    });
  });

  group('setAnswer', () {
    test('refuses to edit a published key', () {
      final result = AnswerKeyPolicy.setAnswer(
        _key(isPublished: true),
        questionNumber: 1,
        option: 'A',
        totalQuestions: 3,
      );
      expect(result.key, isNull);
      expect(result.failure, isNotNull);
    });

    test('refuses a question number out of range', () {
      final result = AnswerKeyPolicy.setAnswer(
        _key(),
        questionNumber: 4,
        option: 'A',
        totalQuestions: 3,
      );
      expect(result.key, isNull);
      expect(result.failure, isNotNull);
    });

    test('refuses an option outside A-D', () {
      final result = AnswerKeyPolicy.setAnswer(
        _key(),
        questionNumber: 1,
        option: 'E',
        totalQuestions: 3,
      );
      expect(result.key, isNull);
      expect(result.failure, isNotNull);
    });

    test('adds a new answer and updates an existing one', () {
      final added = AnswerKeyPolicy.setAnswer(
        _key(),
        questionNumber: 1,
        option: 'A',
        totalQuestions: 3,
      );
      expect(added.key!.optionFor(1), 'A');

      final updated = AnswerKeyPolicy.setAnswer(
        added.key!,
        questionNumber: 1,
        option: 'C',
        totalQuestions: 3,
      );
      expect(updated.key!.optionFor(1), 'C');
      expect(updated.key!.entries, hasLength(1));
    });
  });

  group('changedQuestions', () {
    test('finds only the questions whose answer differs', () {
      final v1 = _key(
        entries: const <AnswerKeyEntry>[
          AnswerKeyEntry(questionNumber: 1, correctOption: 'A'),
          AnswerKeyEntry(questionNumber: 2, correctOption: 'B'),
          AnswerKeyEntry(questionNumber: 3, correctOption: 'C'),
        ],
      );
      final v2 = _key(
        version: 2,
        entries: const <AnswerKeyEntry>[
          AnswerKeyEntry(questionNumber: 1, correctOption: 'A'),
          AnswerKeyEntry(questionNumber: 2, correctOption: 'D'),
          AnswerKeyEntry(questionNumber: 3, correctOption: 'C'),
        ],
      );
      expect(AnswerKeyPolicy.changedQuestions(v1, v2), <int>[2]);
    });
  });
}
