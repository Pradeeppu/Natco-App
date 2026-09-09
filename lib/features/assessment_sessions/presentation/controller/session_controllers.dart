/// Providers for the session screens.
///
/// A session is not paginated (`SessionRepository`'s own doc explains why),
/// so this is a plain `FutureProvider.family` rather than a
/// `PagedListController` — matching `hierarchy_providers.dart`'s pattern for
/// the same reason: Riverpod 3 does not export family provider types.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';

// Named `assessmentSessionProvider` rather than `sessionProvider`: the latter
// is already `SessionController`'s provider for the signed-in user's own
// auth session, in `app/config/service_locator.dart`.
final assessmentSessionProvider =
    FutureProvider.family<AssessmentSession, String>((
      Ref ref,
      String sessionId,
    ) async {
      final Result<AssessmentSession> result = await ref
          .watch(sessionRepositoryProvider)
          .getSession(sessionId);
      return switch (result) {
        Success<AssessmentSession>(:final AssessmentSession value) => value,
        FailureResult<AssessmentSession>(:final failure) => throw failure,
      };
    });
