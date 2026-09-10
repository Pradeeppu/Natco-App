/// An entry in the sync queue.
library;

import 'package:natco_app/features/sync/domain/entity/sync_status.dart';

final class SyncQueueEntry {
  const SyncQueueEntry({
    required this.syncId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payloadRef,
    required this.idempotencyKey,
    required this.createdAt,
    required this.attemptCount,
    this.lastAttemptAt,
    this.nextAttemptAt,
    required this.status,
    this.errorMessage,
    this.errorCode,
  });

  final String syncId;
  final String entityType;
  final String entityId;
  final String operation;
  final String payloadRef;
  final String idempotencyKey;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;
  final SyncStatus status;
  final String? errorMessage;
  final String? errorCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'syncId': syncId,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation,
    'payloadRef': payloadRef,
    'idempotencyKey': idempotencyKey,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'attemptCount': attemptCount,
    'lastAttemptAt': lastAttemptAt?.toUtc().toIso8601String(),
    'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
    'status': status.wireName,
    'errorMessage': errorMessage,
    'errorCode': errorCode,
  };

  static SyncQueueEntry? tryFromJson(Map<String, Object?> json) {
    final String? syncId = json['syncId'] as String?;
    final String? entityType = json['entityType'] as String?;
    final String? entityId = json['entityId'] as String?;
    final String? operation = json['operation'] as String?;
    final String? payloadRef = json['payloadRef'] as String?;
    final String? idempotencyKey = json['idempotencyKey'] as String?;
    final String? createdAtStr = json['createdAt'] as String?;
    final int? attemptCount = json['attemptCount'] as int?;
    final SyncStatus? status = SyncStatus.tryFromWireName(json['status'] as String?);

    if (syncId == null ||
        entityType == null ||
        entityId == null ||
        operation == null ||
        payloadRef == null ||
        idempotencyKey == null ||
        createdAtStr == null ||
        attemptCount == null ||
        status == null) {
      return null;
    }

    final DateTime? createdAt = DateTime.tryParse(createdAtStr);
    if (createdAt == null) {
      return null;
    }

    final Object? lastAttemptAtStr = json['lastAttemptAt'];
    final Object? nextAttemptAtStr = json['nextAttemptAt'];

    return SyncQueueEntry(
      syncId: syncId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payloadRef: payloadRef,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      attemptCount: attemptCount,
      lastAttemptAt: lastAttemptAtStr is String ? DateTime.tryParse(lastAttemptAtStr) : null,
      nextAttemptAt: nextAttemptAtStr is String ? DateTime.tryParse(nextAttemptAtStr) : null,
      status: status,
      errorMessage: json['errorMessage'] as String?,
      errorCode: json['errorCode'] as String?,
    );
  }

  /// [clearNextAttemptAt] and [clearError] exist because a plain `?? this.x`
  /// copyWith cannot express "clear this field" — passing `nextAttemptAt:
  /// null` would just keep the old value, which is exactly wrong for
  /// `SyncEngine.retryFailedNow()`: it needs to actually drop a stale future
  /// `nextAttemptAt` from the last backoff, not carry it into the reset
  /// entry. Same convention `PagedListState.copyWith` uses for its nullable
  /// fields.
  SyncQueueEntry copyWith({
    String? syncId,
    String? entityType,
    String? entityId,
    String? operation,
    String? payloadRef,
    String? idempotencyKey,
    DateTime? createdAt,
    int? attemptCount,
    DateTime? lastAttemptAt,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    SyncStatus? status,
    String? errorMessage,
    String? errorCode,
    bool clearError = false,
  }) => SyncQueueEntry(
    syncId: syncId ?? this.syncId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payloadRef: payloadRef ?? this.payloadRef,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    createdAt: createdAt ?? this.createdAt,
    attemptCount: attemptCount ?? this.attemptCount,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    nextAttemptAt: clearNextAttemptAt
        ? null
        : (nextAttemptAt ?? this.nextAttemptAt),
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
  );

  @override
  bool operator ==(Object other) =>
      other is SyncQueueEntry &&
      other.syncId == syncId &&
      other.entityType == entityType &&
      other.entityId == entityId &&
      other.operation == operation &&
      other.payloadRef == payloadRef &&
      other.idempotencyKey == idempotencyKey &&
      other.createdAt == createdAt &&
      other.attemptCount == attemptCount &&
      other.lastAttemptAt == lastAttemptAt &&
      other.nextAttemptAt == nextAttemptAt &&
      other.status == status &&
      other.errorMessage == errorMessage &&
      other.errorCode == errorCode;

  @override
  int get hashCode => Object.hash(
    syncId,
    entityType,
    entityId,
    operation,
    payloadRef,
    idempotencyKey,
    createdAt,
    attemptCount,
    lastAttemptAt,
    nextAttemptAt,
    status,
    errorMessage,
    errorCode,
  );

  @override
  String toString() => 'SyncQueueEntry($syncId, $entityType, $operation, ${status.wireName})';
}
