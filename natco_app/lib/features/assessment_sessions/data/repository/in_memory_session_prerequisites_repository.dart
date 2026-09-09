/// In-memory [SessionPrerequisitesRepository]. Used by demo mode and the test
/// suite — the same posture as every other in-memory repository in this app.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_prerequisites_repository.dart';

final class InMemorySessionPrerequisitesRepository
    implements SessionPrerequisitesRepository {
  final Map<String, SessionPrerequisites> _byAssignmentId =
      <String, SessionPrerequisites>{};

  @override
  Future<Result<SessionPrerequisites?>> get(String assignmentId) async =>
      ok(_byAssignmentId[assignmentId]);

  @override
  Future<Result<void>> save(SessionPrerequisites prerequisites) async {
    _byAssignmentId[prerequisites.assignmentId] = prerequisites;
    return ok(null);
  }

  @override
  Future<Result<List<SessionPrerequisites>>> listDownloaded() async =>
      ok(List<SessionPrerequisites>.of(_byAssignmentId.values));
}
