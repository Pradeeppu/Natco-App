/// Local cache of [SessionPrerequisites], keyed by assignment.
///
/// Pure storage — no network call lives behind this interface. Populating it
/// is `SessionPrerequisitesDownloader`'s job, which does need a connection;
/// reading it back never does.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';

abstract interface class SessionPrerequisitesRepository {
  Future<Result<SessionPrerequisites?>> get(String assignmentId);

  Future<Result<void>> save(SessionPrerequisites prerequisites);

  /// Every assignment currently downloaded for offline use.
  Future<Result<List<SessionPrerequisites>>> listDownloaded();
}
