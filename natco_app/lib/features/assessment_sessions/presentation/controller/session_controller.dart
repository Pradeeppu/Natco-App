/// Drives one live session: loads it, auto-advances a freshly-started
/// session into `IN_PROGRESS`, and ends it.
///
/// Not a family provider, the same reasoning `StudentsListController`
/// documents: Riverpod's hand-written `Notifier` has no family support in
/// this version, and [viewSession] plays the role a family argument would.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/assessment_sessions_repository.dart';

final class SessionDetailState {
  const SessionDetailState({
    required this.sessionId,
    required this.isLoading,
    this.session,
    this.failure,
  });

  SessionDetailState.initial(String sessionId)
    : this(sessionId: sessionId, isLoading: true);

  final String sessionId;
  final AssessmentSession? session;
  final bool isLoading;
  final Failure? failure;

  SessionDetailState copyWith({
    AssessmentSession? session,
    bool? isLoading,
    Failure? failure,
    bool clearFailure = false,
  }) => SessionDetailState(
    sessionId: sessionId,
    session: session ?? this.session,
    isLoading: isLoading ?? this.isLoading,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

final class SessionController extends Notifier<SessionDetailState> {
  late AssessmentSessionsRepository _repository;

  @override
  SessionDetailState build() {
    _repository = ref.watch(assessmentSessionsRepositoryProvider);
    return SessionDetailState.initial('');
  }

  /// Points this controller at [sessionId]. A no-op if already showing it —
  /// safe to call from `build`.
  Future<void> viewSession(String sessionId) async {
    if (state.sessionId == sessionId) {
      return;
    }
    state = SessionDetailState.initial(sessionId);
    final Result<AssessmentSession?> result = await _repository.getSession(
      sessionId,
    );
    state = switch (result) {
      Success<AssessmentSession?>(:final value) => state.copyWith(
        session: value,
        isLoading: false,
      ),
      FailureResult<AssessmentSession?>(:final failure) => state.copyWith(
        isLoading: false,
        failure: failure,
      ),
    };
    // A session opened right after `startSession` is still `STARTED` — there
    // is no separate "begin capturing" action until Phase 5 adds OMR
    // capture, so opening the screen is itself what moves a session into
    // `IN_PROGRESS`.
    if (state.session?.status == SessionStatus.started) {
      await _advanceTo(SessionStatus.inProgress);
    }
  }

  Future<void> endSession() => _advanceTo(SessionStatus.completed);

  Future<void> _advanceTo(SessionStatus next) async {
    final result = await _repository.setSessionStatus(state.sessionId, next);
    state = switch (result) {
      Success<AssessmentSession>(:final value) => state.copyWith(
        session: value,
        clearFailure: true,
      ),
      FailureResult<AssessmentSession>(:final failure) => state.copyWith(
        failure: failure,
      ),
    };
  }
}

final NotifierProvider<SessionController, SessionDetailState> sessionControllerProvider =
    NotifierProvider<SessionController, SessionDetailState>(
      SessionController.new,
    );
