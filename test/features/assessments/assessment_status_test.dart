/// Tests for [AssessmentStatus]'s transition table.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';

void main() {
  group('AssessmentStatus transitions', () {
    test('draft may only become published', () {
      expect(AssessmentStatus.draft.allowedNext, <AssessmentStatus>{
        AssessmentStatus.published,
      });
    });

    test('published may become active or closed', () {
      expect(AssessmentStatus.published.allowedNext, <AssessmentStatus>{
        AssessmentStatus.active,
        AssessmentStatus.closed,
      });
    });

    test('active may only become closed', () {
      expect(AssessmentStatus.active.allowedNext, <AssessmentStatus>{
        AssessmentStatus.closed,
      });
    });

    test('closed may only become archived', () {
      expect(AssessmentStatus.closed.allowedNext, <AssessmentStatus>{
        AssessmentStatus.archived,
      });
    });

    test('archived is terminal', () {
      expect(AssessmentStatus.archived.allowedNext, isEmpty);
    });

    test('nothing ever returns to draft', () {
      for (final AssessmentStatus status in AssessmentStatus.values) {
        expect(status.canTransitionTo(AssessmentStatus.draft), isFalse);
      }
    });

    test('a skip is refused: draft cannot jump to active', () {
      expect(
        AssessmentStatus.draft.canTransitionTo(AssessmentStatus.active),
        isFalse,
      );
    });
  });

  group('isEditable and acceptsSubmissions', () {
    test('only a draft is editable', () {
      expect(AssessmentStatus.draft.isEditable, isTrue);
      for (final AssessmentStatus status in AssessmentStatus.values) {
        if (status != AssessmentStatus.draft) {
          expect(status.isEditable, isFalse);
        }
      }
    });

    test('published and active accept submissions; nothing else does', () {
      expect(AssessmentStatus.published.acceptsSubmissions, isTrue);
      expect(AssessmentStatus.active.acceptsSubmissions, isTrue);
      expect(AssessmentStatus.draft.acceptsSubmissions, isFalse);
      expect(AssessmentStatus.closed.acceptsSubmissions, isFalse);
      expect(AssessmentStatus.archived.acceptsSubmissions, isFalse);
    });
  });

  group('Assessment.isReadyForSessions', () {
    Assessment build({
      required AssessmentStatus status,
      int? publishedAnswerKeyVersion,
    }) => Assessment(
      assessmentId: 'as_1',
      assessmentName: 'Test',
      academicYear: '2026-27',
      grade: '5',
      subject: 'Maths',
      totalQuestions: 10,
      marksPerQuestion: 1,
      status: status,
      omrTemplateId: 'tpl_1',
      publishedAnswerKeyVersion: publishedAnswerKeyVersion,
      createdBy: 'u1',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    test('published with no key is not ready', () {
      expect(
        build(status: AssessmentStatus.published).isReadyForSessions,
        isFalse,
      );
    });

    test('published with a key is ready', () {
      expect(
        build(
          status: AssessmentStatus.published,
          publishedAnswerKeyVersion: 1,
        ).isReadyForSessions,
        isTrue,
      );
    });

    test('draft with a key is still not ready', () {
      expect(
        build(
          status: AssessmentStatus.draft,
          publishedAnswerKeyVersion: 1,
        ).isReadyForSessions,
        isFalse,
      );
    });

    test('closed with a key is not ready', () {
      expect(
        build(
          status: AssessmentStatus.closed,
          publishedAnswerKeyVersion: 1,
        ).isReadyForSessions,
        isFalse,
      );
    });
  });
}
