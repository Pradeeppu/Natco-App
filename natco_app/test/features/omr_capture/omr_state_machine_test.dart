/// Tests for the OMR processing state machine — the transitions Phase 5
/// (capture) and Phase 6 (the detection engine) implement; see
/// `OmrStateMachine`'s own doc comment for why the rest are deferred rather
/// than guessed.
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

  group('Phase 6 — the detection engine', () {
    test('quality-checked moves to processing', () {
      final result = machine.transition(
        OmrProcessingStatus.qualityChecked,
        OmrProcessingStatus.processing,
      );
      expect(result.valueOrNull, OmrProcessingStatus.processing);
    });

    test('processing moves to processing-failed when markers cannot be found', () {
      final result = machine.transition(
        OmrProcessingStatus.processing,
        OmrProcessingStatus.processingFailed,
      );
      expect(result.valueOrNull, OmrProcessingStatus.processingFailed);
    });

    test('processing-failed can retry back into processing', () {
      final result = machine.transition(
        OmrProcessingStatus.processingFailed,
        OmrProcessingStatus.processing,
      );
      expect(result.valueOrNull, OmrProcessingStatus.processing);
    });

    test('processing moves to processed once every question is classified', () {
      final result = machine.transition(
        OmrProcessingStatus.processing,
        OmrProcessingStatus.processed,
      );
      expect(result.valueOrNull, OmrProcessingStatus.processed);
    });

    test('processed moves to needs-validation or ready-for-scoring', () {
      expect(
        machine
            .transition(
              OmrProcessingStatus.processed,
              OmrProcessingStatus.needsValidation,
            )
            .valueOrNull,
        OmrProcessingStatus.needsValidation,
      );
      expect(
        machine
            .transition(
              OmrProcessingStatus.processed,
              OmrProcessingStatus.readyForScoring,
            )
            .valueOrNull,
        OmrProcessingStatus.readyForScoring,
      );
    });

    test('rejects skipping straight from quality-checked to processed', () {
      final result = machine.transition(
        OmrProcessingStatus.qualityChecked,
        OmrProcessingStatus.processed,
      );
      expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
    });

    test('rejects a transition into stages this phase does not reach', () {
      final result = machine.transition(
        OmrProcessingStatus.processed,
        OmrProcessingStatus.scored,
      );
      expect(result.failureOrNull, isA<IllegalStateTransitionFailure>());
    });
  });
}
