/// Tests for the session status state machine.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';

void main() {
  test('each status transitions only to the very next one', () {
    const List<SessionStatus> order = SessionStatus.values;
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

  test('cannot skip from started straight to completed', () {
    expect(
      SessionStatus.started.canTransitionTo(SessionStatus.completed),
      isFalse,
    );
  });

  test('cannot move backward from completed to in progress', () {
    expect(
      SessionStatus.completed.canTransitionTo(SessionStatus.inProgress),
      isFalse,
    );
  });

  test('wire names round-trip', () {
    for (final SessionStatus status in SessionStatus.values) {
      expect(SessionStatus.tryFromWireName(status.wireName), status);
    }
    expect(SessionStatus.tryFromWireName('NOT_A_STATUS'), isNull);
  });
}
