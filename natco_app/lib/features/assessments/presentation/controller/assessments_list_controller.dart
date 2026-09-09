/// Drives the paginated, searchable, status-filterable assessments list.
///
/// Not scope-restricted, the same posture as `AssessmentsRepository.
/// listAssessments` itself — see `Assessment`'s doc comment for why the
/// definition is visible to anyone holding `viewAssessments`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/repository/assessments_repository.dart';

final class AssessmentsListState {
  const AssessmentsListState({
    required this.query,
    required this.status,
    required this.assessments,
    required this.nextCursor,
    required this.isLoading,
    required this.isLoadingMore,
    this.failure,
  });

  AssessmentsListState.initial()
    : this(
        query: '',
        status: null,
        assessments: const <Assessment>[],
        nextCursor: null,
        isLoading: true,
        isLoadingMore: false,
      );

  final String query;
  final AssessmentStatus? status;
  final List<Assessment> assessments;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final Failure? failure;

  bool get hasMore => nextCursor != null;

  AssessmentsListState copyWith({
    String? query,
    AssessmentStatus? status,
    bool clearStatus = false,
    List<Assessment>? assessments,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoading,
    bool? isLoadingMore,
    Failure? failure,
    bool clearFailure = false,
  }) => AssessmentsListState(
    query: query ?? this.query,
    status: clearStatus ? null : (status ?? this.status),
    assessments: assessments ?? this.assessments,
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

final class AssessmentsListController extends Notifier<AssessmentsListState> {
  late AssessmentsRepository _repository;

  @override
  AssessmentsListState build() {
    _repository = ref.watch(assessmentsRepositoryProvider);
    Future<void>.microtask(() => _load(reset: true));
    return AssessmentsListState.initial();
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) {
      return;
    }
    await _load(reset: false);
  }

  Future<void> search(String query) async {
    state = state.copyWith(query: query);
    await _load(reset: true);
  }

  Future<void> filterByStatus(AssessmentStatus? status) async {
    state = status == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(status: status);
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    state = reset
        ? state.copyWith(isLoading: true, clearFailure: true)
        : state.copyWith(isLoadingMore: true, clearFailure: true);

    final Result<Page<Assessment>> result = await _repository.listAssessments(
      query: state.query.isEmpty ? null : state.query,
      status: state.status,
      request: PageRequest(cursor: reset ? null : state.nextCursor),
    );

    state = switch (result) {
      Success<Page<Assessment>>(:final value) => state.copyWith(
        assessments: <Assessment>[
          ...(reset ? const <Assessment>[] : state.assessments),
          ...value.items,
        ],
        nextCursor: value.nextCursor,
        clearNextCursor: value.nextCursor == null,
        isLoading: false,
        isLoadingMore: false,
      ),
      FailureResult<Page<Assessment>>(:final failure) => state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        failure: failure,
      ),
    };
  }
}

final NotifierProvider<AssessmentsListController, AssessmentsListState>
assessmentsListProvider =
    NotifierProvider<AssessmentsListController, AssessmentsListState>(
      AssessmentsListController.new,
    );
