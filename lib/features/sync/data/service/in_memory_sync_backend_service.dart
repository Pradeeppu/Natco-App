/// In-memory stand-in backend for demo mode.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/service/sync_engine.dart';

final class InMemorySyncBackendService implements SyncBackendService {
  InMemorySyncBackendService({
    this.simulatedLatency = const Duration(milliseconds: 500),
  });

  final Duration simulatedLatency;
  final Set<String> _receipts = <String>{};

  @override
  Future<Result<void>> syncPayload({
    required String entityType,
    required String operation,
    required String payloadRef,
    required String idempotencyKey,
  }) async {
    if (simulatedLatency > Duration.zero) {
      await Future<void>.delayed(simulatedLatency);
    }

    if (_receipts.contains(idempotencyKey)) {
      // Idempotency hit: already processed
      return ok(null);
    }

    // Simulate processing
    _receipts.add(idempotencyKey);
    return ok(null);
  }
}
