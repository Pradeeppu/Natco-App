/// Drives a single school's paginated, searchable student list, plus the CSV
/// import flow.
///
/// The exit criterion this exists to satisfy: a 2,000-student school scrolls
/// rather than loads (requirement section 42). Every page fetched is appended
/// to what is already on screen; nothing here ever asks the repository for
/// "all students".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/domain/entity/student_import_report.dart';
import 'package:natco_app/features/students/domain/repository/students_repository.dart';
import 'package:natco_app/features/students/domain/service/student_csv_importer.dart';

final class StudentsListState {
  const StudentsListState({
    required this.schoolId,
    required this.query,
    required this.grade,
    required this.section,
    required this.students,
    required this.nextCursor,
    required this.isLoading,
    required this.isLoadingMore,
    this.failure,
    this.lastImportReport,
    this.isImporting = false,
  });

  StudentsListState.initial(String schoolId)
    : this(
        schoolId: schoolId,
        query: '',
        grade: null,
        section: null,
        students: const <Student>[],
        nextCursor: null,
        isLoading: true,
        isLoadingMore: false,
      );

  final String schoolId;
  final String query;
  final String? grade;
  final String? section;
  final List<Student> students;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final Failure? failure;

  /// The most recent CSV import's outcome, shown once and then dismissed —
  /// never silently: every rejected row stays visible until the person
  /// running the import acknowledges it (requirement section 11).
  final StudentImportReport? lastImportReport;
  final bool isImporting;

  bool get hasMore => nextCursor != null;

  StudentsListState copyWith({
    String? query,
    String? grade,
    bool clearGrade = false,
    String? section,
    bool clearSection = false,
    List<Student>? students,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoading,
    bool? isLoadingMore,
    Failure? failure,
    bool clearFailure = false,
    StudentImportReport? lastImportReport,
    bool clearImportReport = false,
    bool? isImporting,
  }) => StudentsListState(
    schoolId: schoolId,
    query: query ?? this.query,
    grade: clearGrade ? null : (grade ?? this.grade),
    section: clearSection ? null : (section ?? this.section),
    students: students ?? this.students,
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
    lastImportReport: clearImportReport
        ? null
        : (lastImportReport ?? this.lastImportReport),
    isImporting: isImporting ?? this.isImporting,
  );
}

/// One controller shared by the Students screen, pointed at a school with
/// [viewSchool].
///
/// Riverpod's hand-written `Notifier` (as opposed to a `@riverpod`-generated
/// one) takes no build argument, so this does not use a family provider —
/// the project deliberately keeps `riverpod_generator` out of the dependency
/// list to hold down the build_runner surface (docs/09-dependencies.md).
/// [viewSchool] plays the role a family argument would: switching schools
/// resets pagination and reloads; re-requesting the same school is a no-op,
/// so a widget can call it from `build` without triggering a reload loop.
final class StudentsListController extends Notifier<StudentsListState> {
  late StudentsRepository _repository;
  late AccessScope _scope;

  @override
  StudentsListState build() {
    _repository = ref.watch(studentsRepositoryProvider);
    _scope = ref.watch(sessionProvider).authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
    return StudentsListState.initial('');
  }

  /// Points this controller at [schoolId]. A no-op if already showing it.
  Future<void> viewSchool(String schoolId) async {
    if (state.schoolId == schoolId) {
      return;
    }
    state = StudentsListState.initial(schoolId);
    await _load(reset: true);
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

  Future<void> filterByGrade(String? grade) async {
    state = grade == null
        ? state.copyWith(clearGrade: true)
        : state.copyWith(grade: grade);
    await _load(reset: true);
  }

  Future<void> filterBySection(String? section) async {
    state = section == null
        ? state.copyWith(clearSection: true)
        : state.copyWith(section: section);
    await _load(reset: true);
  }

  void dismissImportReport() =>
      state = state.copyWith(clearImportReport: true);

  /// Parses [csvText] and imports every readable row against this school.
  ///
  /// Parse errors (unreadable rows) and persistence rejections (duplicates)
  /// are both folded into one [StudentImportReport] so the caller sees a
  /// single, complete picture of what happened — never two separate dialogs
  /// for two halves of the same operation.
  Future<void> importCsv(String csvText) async {
    state = state.copyWith(isImporting: true, clearImportReport: true);
    const StudentCsvImporter importer = StudentCsvImporter();
    final StudentCsvParseResult parsed = importer.parse(csvText);

    if (parsed.rows.isEmpty) {
      state = state.copyWith(
        isImporting: false,
        lastImportReport: StudentImportReport(
          totalRows: parsed.errors.length,
          createdCount: 0,
          parseErrors: parsed.errors,
          rejections: const <StudentImportRejection>[],
        ),
      );
      return;
    }

    final Result<StudentImportReport> result = await _repository.importStudents(
      schoolId: state.schoolId,
      rows: parsed.rows,
    );

    state = switch (result) {
      Success<StudentImportReport>(:final value) => state.copyWith(
        isImporting: false,
        lastImportReport: StudentImportReport(
          totalRows: value.totalRows + parsed.errors.length,
          createdCount: value.createdCount,
          parseErrors: parsed.errors,
          rejections: value.rejections,
        ),
      ),
      FailureResult<StudentImportReport>(:final failure) => state.copyWith(
        isImporting: false,
        failure: failure,
      ),
    };

    if (result.isSuccess) {
      await _load(reset: true);
    }
  }

  Future<void> _load({required bool reset}) async {
    state = reset
        ? state.copyWith(isLoading: true, clearFailure: true)
        : state.copyWith(isLoadingMore: true, clearFailure: true);

    final Result<Page<Student>> result = await _repository.listStudents(
      scope: _scope,
      schoolId: state.schoolId,
      grade: state.grade,
      section: state.section,
      query: state.query.isEmpty ? null : state.query,
      request: PageRequest(cursor: reset ? null : state.nextCursor),
    );

    state = switch (result) {
      Success<Page<Student>>(:final value) => state.copyWith(
        students: <Student>[
          ...(reset ? const <Student>[] : state.students),
          ...value.items,
        ],
        nextCursor: value.nextCursor,
        clearNextCursor: value.nextCursor == null,
        isLoading: false,
        isLoadingMore: false,
      ),
      FailureResult<Page<Student>>(:final failure) => state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        failure: failure,
      ),
    };
  }
}

final NotifierProvider<StudentsListController, StudentsListState>
studentsListProvider =
    NotifierProvider<StudentsListController, StudentsListState>(
      StudentsListController.new,
    );
