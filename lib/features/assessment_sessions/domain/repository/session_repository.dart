/// Assessment sessions (docs/02-data-model.md §6, requirement §15).
///
/// Unlike every repository before it, this one is **local-first**. A teacher
/// standing in a classroom with no signal must be able to create a session,
/// mark attendance and capture sheets without waiting on a server, and a
/// force-stop must lose nothing (Critical Rule 12). So every write here lands
/// in local storage first and is uploaded afterwards by the sync engine
/// (phase 9); the network is an eventual-consistency detail, never a
/// precondition.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

abstract interface class SessionRepository {
  /// Sessions this user can see, newest first.
  ///
  /// Not paginated: a session list is bounded by how many sittings one person
  /// runs, which is small. Adding cursors here would be ceremony over a list
  /// that fits on a screen.
  Future<Result<List<AssessmentSession>>> listSessions({
    required AccessScope scope,
    String? assessmentId,
    bool openOnly = false,
  });

  Future<Result<AssessmentSession>> getSession(String sessionId);

  /// Creates a session and its roster.
  ///
  /// The roster is built here, from the students currently registered in the
  /// class, and *stored on the session*. Two reasons: the roster must render
  /// with no network, and a child who transfers out next week must not
  /// disappear from a sitting they actually sat.
  Future<Result<AssessmentSession>> createSession({
    required String assessmentId,
    required String schoolId,
    required String grade,
    required String section,
    required String actorUserId,
    required String actorRole,
  });

  /// Moves a session through its lifecycle, refusing illegal transitions.
  ///
  /// [reason] is required when abandoning: a sitting that ended early is a
  /// fact somebody will need explained, and "abandoned" with no cause is not
  /// an explanation.
  Future<Result<AssessmentSession>> changeStatus(
    String sessionId, {
    required SessionStatus next,
    String? reason,
    required String actorUserId,
    required String actorRole,
  });

  /// Marks a student absent, or undoes that.
  ///
  /// Refused once a sheet exists for them: the sheet is evidence they were
  /// there, and a record that says both is a record nobody can act on.
  Future<Result<AssessmentSession>> setAttendance(
    String sessionId, {
    required String studentId,
    required AttendanceState attendance,
    String? note,
    required String actorUserId,
    required String actorRole,
  });

  /// Links a captured sheet to a roster entry.
  ///
  /// Called by the capture flow once an image is durably on disk (phase 5).
  Future<Result<AssessmentSession>> attachOmr(
    String sessionId, {
    required String studentId,
    required String omrId,
    required String actorUserId,
    required String actorRole,
  });
}
