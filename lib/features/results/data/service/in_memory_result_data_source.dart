/// In-memory [ResultDataSource]. Backs demo mode and tests.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/results/data/service/result_data_source.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';

final class InMemoryResultDataSource implements ResultDataSource {
  InMemoryResultDataSource({List<AssessmentResult> results = const <AssessmentResult>[]})
    : _results = <String, AssessmentResult>{
        for (final AssessmentResult r in results) r.resultId: r,
      };

  final Map<String, AssessmentResult> _results;

  @override
  Future<Result<Page<AssessmentResult>>> listResults({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) async {
    final List<AssessmentResult> matching =
        _results.values
            .where(
              (AssessmentResult r) =>
                  r.assessmentId == assessmentId && !r.isSuperseded,
            )
            .where(
              (AssessmentResult r) => scope.covers(
                ScopeTarget(
                  stateId: r.stateId,
                  districtId: r.districtId,
                  clusterId: r.clusterId,
                  schoolId: r.schoolId,
                  grade: r.grade,
                  section: r.section,
                ),
              ),
            )
            .toList()
          ..sort(
            (AssessmentResult a, AssessmentResult b) =>
                b.marksObtained.compareTo(a.marksObtained),
          );

    final int offset = cursor is int ? cursor : 0;
    final int end = (offset + pageSize).clamp(0, matching.length);
    final List<AssessmentResult> items = offset >= matching.length
        ? const <AssessmentResult>[]
        : matching.sublist(offset, end);
    final bool hasMore = end < matching.length;
    return ok((
      items: items,
      nextCursor: hasMore ? end : null,
      hasMore: hasMore,
    ));
  }

  @override
  Future<Result<AssessmentResult?>> getCurrentResultForStudent({
    required String assessmentId,
    required String studentId,
  }) async {
    for (final AssessmentResult r in _results.values) {
      if (r.assessmentId == assessmentId &&
          r.studentId == studentId &&
          !r.isSuperseded) {
        return ok(r);
      }
    }
    return ok(null);
  }

  @override
  Future<Result<AssessmentResult?>> getCurrentResultForSubmission(
    String omrId,
  ) async {
    for (final AssessmentResult r in _results.values) {
      if (r.omrId == omrId && !r.isSuperseded) {
        return ok(r);
      }
    }
    return ok(null);
  }

  @override
  Future<Result<AssessmentResult>> saveResult(AssessmentResult result) async {
    _results[result.resultId] = result;
    return ok(result);
  }
}
