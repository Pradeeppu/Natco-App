/// Tests for the linear, forward-only status state machines.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assignment_status.dart';

void main() {
  group('AssessmentStatus', () {
    test('each status transitions only to the very next one', () {
      const List<AssessmentStatus> order = AssessmentStatus.values;
      for (int i = 0; i < order.length; i++) {
        for (int j = 0; j < order.length; j++) {
          final bool expected = j == i + 1;
          expect(
            order[i].canTransitionTo(order[j]),
            expected,
            reason: '${order[i]} -> ${order[j]}',
          );
        }
      }
    });

    test('cannot skip a step', () {
      expect(
        AssessmentStatus.draft.canTransitionTo(AssessmentStatus.active),
        isFalse,
      );
    });

    test('cannot move backward', () {
      expect(
        AssessmentStatus.active.canTransitionTo(AssessmentStatus.published),
        isFalse,
      );
    });

    test('the terminal status has no legal next step', () {
      expect(
        AssessmentStatus.archived.canTransitionTo(AssessmentStatus.archived),
        isFalse,
      );
    });
  });

  group('AssignmentStatus', () {
    test('each status transitions only to the very next one', () {
      const List<AssignmentStatus> order = AssignmentStatus.values;
      for (int i = 0; i < order.length; i++) {
        for (int j = 0; j < order.length; j++) {
          final bool expected = j == i + 1;
          expect(order[i].canTransitionTo(order[j]), expected);
        }
      }
    });
  });
}
