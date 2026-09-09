/// Pure Dart policy for determining who may resolve sync conflicts.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';

final class SyncConflictPolicy {
  const SyncConflictPolicy();

  /// Enforces that a user can only perform an action on a conflict based on their role
  /// and the entity type.
  /// 
  /// Teachers and scanner operators may only escalate to a review case on anything 
  /// touching scores, validations, or answers. They can never pick a side.
  Result<void> canResolve({
    required UserRole actorRole,
    required String entityType,
    required bool isEscalation,
  }) {
    if (entityType == 'omr_answers' || entityType == 'omr_validations' || entityType == 'score') {
      if (actorRole == UserRole.pstTeacher || actorRole == UserRole.scannerOperator) {
        if (!isEscalation) {
          return err(
            PermissionFailure.denied(
              action: 'resolve conflicts on assessments',
              diagnostic: 'Teacher/Scanner Operator cannot force-resolve data conflicts',
            ),
          );
        }
      }
    }
    
    return ok(null);
  }
}
