/// Tests for the OMR processing state machine — only the transitions
/// Phase 5 (capture) implements; see `OmrStateMachine`'s own doc comment for
/// why the rest are deferred rather than guessed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/service/omr_state_machine.dart';

void main() {
  const OmrStateMachine machine = OmrStateMachine();

  test('captured moves to quality-checked', () {
    final result = machine.transition(
      OmrProcessingStatus.captured,
      OmrProcessingStatus.qualityChecked,
    );
    expect(result.valueOrNull, OmrProcessingStatus.qualityChecked);
  });

  test('quality-checked moves to quality-failed on a fail verdict', () {
    final result = machine.transition(
      OmrProcessingStatus.qualityChecked,
      OmrProcessingStatus.qualityFailed,
    );
    expect(result.valueOrNull, OmrProcessingStatus.qualityFailed);
  });

  test('quality-failed moves back to quality-checked on override', () {
    final result = machine.transition(
      OmrProcessingStatus.qualityFailed,
      OmrProcessingStatus.qualityChecked,
    );
    expect(result.valueOrNull, OmrProcessingStatus.qualityChecked);
  });

  test('rejects skipping straight from captured to quality-failed', () {
    final result = machine.transition(
      OmrProcessingStatus.captured,
      OmrProcessingStatus.qualityFailed,
    );
    expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
  });

  test('rejects a transition into pipeline stages this phase does not reach', () {
    final result = machine.transition(
      OmrProcessingStatus.qualityChecked,
      OmrProcessingStatus.processing,
    );
    expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
  });

  test('rejects a no-op transition to the same status', () {
    final result = machine.transition(
      OmrProcessingStatus.captured,
      OmrProcessingStatus.captured,
    );
    expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
  });

  test('canTransition agrees with transition', () {
    expect(
      machine.canTransition(
        OmrProcessingStatus.captured,
        OmrProcessingStatus.qualityChecked,
      ),
      isTrue,
    );
    expect(
      machine.canTransition(
        OmrProcessingStatus.synced,
        OmrProcessingStatus.captured,
      ),
      isFalse,
    );
  });
}
