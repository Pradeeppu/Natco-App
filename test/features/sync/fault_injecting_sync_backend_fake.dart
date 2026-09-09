/// Fake backend that can simulate network drops.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/service/sync_engine.dart';

final class FaultInjectingSyncBackendFake implements SyncBackendService {
  final Set<String> _receipts = <String>{};
  
  /// Determines if the next network call will pretend to fail.
  bool failNextNetworkCall = false;

  /// Counts how many times the idempotency check prevented a duplicate write.
  int idempotencyShortCircuitCount = 0;
  
  /// Total writes that actually processed.
  int successfulWrites = 0;

  @override
  Future<Result<void>> syncPayload({
    required String entityType,
    required String operation,
    required String payloadRef,
    required String idempotencyKey,
  }) async {
    // 1. Check idempotency receipt BEFORE checking network failure
    if (_receipts.contains(idempotencyKey)) {
      idempotencyShortCircuitCount++;
      return ok(null);
    }

    // 2. Simulate server processing and writing the receipt.
    // In a real scenario, the backend writes to DB + sync_receipts atomically.
    _receipts.add(idempotencyKey);
    successfulWrites++;

    // 3. Network drop happens AFTER server processed, but BEFORE client gets ACK.
    if (failNextNetworkCall) {
      failNextNetworkCall = false; // reset for next call
      return err(NetworkFailure.unreachable(diagnostic: 'Connection dropped mid-flight'));
    }

    return ok(null);
  }
}
