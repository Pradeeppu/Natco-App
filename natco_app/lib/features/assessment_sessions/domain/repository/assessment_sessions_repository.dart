/// A teacher's assessment sessions, as seen by the presentation layer
/// (docs/02-data-model.md section 5).
///
/// [startSession] reads only [SessionPrerequisites] — already-downloaded
/// local data — never a network-backed repository, which is what makes a
/// session startable in airplane mode.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

abstract interface class AssessmentSessionsRepository {
  Future<Result<List<AssessmentSession>>> listSessions({
    required AccessScope scope,
    String? teacherUserId,
  });

  Future<Result<AssessmentSession?>> getSession(String sessionId);

  /// Creates a session directly at [SessionStatus.started] for [section] —
  /// one of the sections [prerequisites] was downloaded for. Fails when
  /// [section] was not part of the download, or has no students in it.
  Future<Result<AssessmentSession>> startSession({
    required SessionPrerequisites prerequisites,
    required String section,
    required int expectedStudentCount,
    required String teacherUserId,
    required String deviceId,
  });

  /// Moves the session one step forward in [SessionStatus]'s linear
  /// lifecycle. Fails with `IllegalStateTransitionFailure` for anything other
  /// than the single legal next step.
  Future<Result<AssessmentSession>> setSessionStatus(
    String sessionId,
    SessionStatus next,
  );
}
