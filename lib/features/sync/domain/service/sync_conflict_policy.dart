/// Pure Dart policy for determining who may resolve sync conflicts.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';

final class SyncConflictPolicy {
  const SyncConflictPolicy();

  /// Enforces that a user can only perform an action on a conflict based on their role
  /// and the entity type.
  /// 
  /// Users without [Permission.resolveSyncConflict] may only escalate to a review case 
  /// on anything touching scores, validations, or answers. They can never pick a side.
  Result<void> canResolve({
    required Authorization authorization,
    required SyncEntityType entityType,
    required bool isEscalation,
  }) {
    if (entityType == SyncEntityType.omrAnswer || 
        entityType == SyncEntityType.omrValidation || 
        entityType == SyncEntityType.score) {
      if (!authorization.can(Permission.resolveSyncConflict)) {
        if (!isEscalation) {
          return err(
            PermissionFailure.denied(
              action: 'resolve conflicts on assessments',
              diagnostic: 'User without resolveSyncConflict cannot force-resolve data conflicts',
            ),
          );
        }
      }
    }
    
    return ok(null);
  }
}
