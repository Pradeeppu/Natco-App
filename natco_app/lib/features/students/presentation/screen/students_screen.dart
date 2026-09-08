/// Paginated, searchable student list for one school, with CSV import.
///
/// `/students` carries no path parameter, so which school is showing comes
/// from a `?schoolId=` query parameter instead: the route table
/// (docs/05-navigation-map.md) is fixed and every declared route already
/// carries its own permission rule, so adding a nested
/// `/students/school/:schoolId` route would duplicate that declaration for no
/// benefit. A teacher whose scope pins exactly one school is sent straight
/// there; anyone with a wider scope picks a school first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/presentation/controller/school_detail_provider.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/presentation/controller/students_list_controller.dart';
import 'package:natco_app/features/students/presentation/widget/csv_import_dialog.dart';
import 'package:natco_app/features/students/presentation/widget/student_form_dialog.dart';

String _studentsPathFor(String schoolId) => Uri(
  path: RoutePaths.students,
  queryParameters: <String, String>{'schoolId': schoolId},
).toString();

final class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  String? _requestedSchoolId;

  @override
  Widget build(BuildContext context) {
    final String? schoolId = GoRouterState.of(
      context,
    ).uri.queryParameters['schoolId'];
    final AccessScope? scope = ref
        .watch(sessionProvider)
        .authorization
        .user
        ?.scope;

    if (schoolId == null) {
      if (scope != null &&
          scope.level == ScopeLevel.school &&
          scope.schoolIds.length == 1) {
        final String onlySchool = scope.schoolIds.single;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go(_studentsPathFor(onlySchool));
          }
        });
        return const Scaffold(body: LoadingView());
      }
      return const Scaffold(
        appBar: null,
        body: SafeArea(child: _SchoolPicker()),
      );
    }

    if (_requestedSchoolId != schoolId) {
      _requestedSchoolId = schoolId;
      Future<void>.microtask(
        () => ref.read(studentsListProvider.notifier).viewSchool(schoolId),
      );
    }

    return _StudentsListBody(schoolId: schoolId);
  }
}

/// Shown when the signed-in user's scope covers more than one school: they
/// pick which one to browse.
final class _SchoolPicker extends ConsumerStatefulWidget {
  const _SchoolPicker();

  @override
  ConsumerState<_SchoolPicker> createState() => _SchoolPickerState();
}

class _SchoolPickerState extends ConsumerState<_SchoolPicker> {
  final TextEditingController _searchController = TextEditingController();
  List<School> _results = const <School>[];
  bool _isLoading = true;
  Failure? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final AccessScope scope =
        ref.read(sessionProvider).authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
    final result = await ref
        .read(schoolsRepositoryProvider)
        .listSchools(scope: scope, query: query.isEmpty ? null : query);
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _error = result.failureOrNull;
      _results = result.valueOrNull?.items ?? const <School>[];
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          'Choose a school',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search schools',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: _search,
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _isLoading
            ? const LoadingView()
            : _error != null
            ? FailureView(
                failure: _error!,
                onRetry: () => _search(_searchController.text),
              )
            : _results.isEmpty
            ? const EmptyView(
                title: 'No schools found',
                icon: Icons.school_outlined,
              )
            : ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final School school = _results[index];
                  return ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: Text(school.schoolName),
                    subtitle: Text(school.schoolCode),
                    onTap: () =>
                        context.go(_studentsPathFor(school.schoolId)),
                  );
                },
              ),
      ),
    ],
  );
}

final class _StudentsListBody extends ConsumerStatefulWidget {
  const _StudentsListBody({required this.schoolId});

  final String schoolId;

  @override
  ConsumerState<_StudentsListBody> createState() => _StudentsListBodyState();
}

class _StudentsListBodyState extends ConsumerState<_StudentsListBody> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(studentsListProvider.notifier).loadMore();
    }
  }

  Future<void> _showImportDialog() async {
    await showCsvImportDialog(
      context: context,
      onImport: (String csvText) async {
        await ref.read(studentsListProvider.notifier).importCsv(csvText);
        return ref.read(studentsListProvider).lastImportReport;
      },
    );
  }

  Future<void> _showAddStudentDialog(School school) async {
    await showStudentFormDialog(
      context: context,
      allowedGrades: school.grades,
      allowedMediums: school.mediumsOfInstruction,
      onSubmit: (StudentDraft draft) async {
        final result = await ref
            .read(studentsRepositoryProvider)
            .createStudent(
              schoolId: widget.schoolId,
              studentName: draft.studentName,
              gender: draft.gender,
              grade: draft.grade,
              section: draft.section,
              mediumOfInstruction: draft.mediumOfInstruction,
              language: draft.language,
              dateOfBirth: draft.dateOfBirth,
              electiveSubject: draft.electiveSubject,
            );
        return result.failureOrNull;
      },
    );
    await ref.read(studentsListProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final StudentsListState state = ref.watch(studentsListProvider);
    final AsyncValue<School?> schoolAsync = ref.watch(
      schoolDetailProvider(widget.schoolId),
    );
    final Authorization authorization = ref
        .watch(sessionProvider)
        .authorization;
    final bool canImport = authorization.can(Permission.importStudents);
    final bool canManage = authorization.can(Permission.manageStudents);
    final School? school = schoolAsync.value;

    ref.listen<StudentsListState>(studentsListProvider, (
      StudentsListState? previous,
      StudentsListState next,
    ) {
      if (next.lastImportReport != null &&
          previous?.lastImportReport != next.lastImportReport) {
        // The dialog itself renders the report; nothing to do here beyond
        // letting the list below pick up newly imported rows via `refresh`,
        // which `importCsv` already triggers on success.
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(school?.schoolName ?? 'Students'),
        actions: <Widget>[
          if (canImport)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Import CSV',
              onPressed: _showImportDialog,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search students',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (String value) =>
                    ref.read(studentsListProvider.notifier).search(value),
              ),
            ),
            if (school != null && school.grades.isNotEmpty)
              _FilterRow(school: school),
            Expanded(child: _buildList(state)),
          ],
        ),
      ),
      floatingActionButton: canManage && school != null
          ? FloatingActionButton.extended(
              onPressed: () => _showAddStudentDialog(school),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add'),
            )
          : null,
    );
  }

  Widget _buildList(StudentsListState state) {
    if (state.isLoading && state.students.isEmpty) {
      return const LoadingView();
    }
    if (state.failure != null && state.students.isEmpty) {
      return FailureView(
        failure: state.failure!,
        onRetry: () => ref.read(studentsListProvider.notifier).refresh(),
      );
    }
    if (state.students.isEmpty) {
      return EmptyView(
        title: 'No students found',
        message: state.query.isEmpty
            ? 'No students are enrolled here yet.'
            : 'No results for "${state.query}".',
        icon: Icons.groups_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(studentsListProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: state.students.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          if (index >= state.students.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final Student student = state.students[index];
          return ListTile(
            leading: CircleAvatar(
              child: Text(
                student.studentName.isEmpty
                    ? '?'
                    : student.studentName[0].toUpperCase(),
              ),
            ),
            title: Text(student.studentName),
            subtitle: Text('Grade ${student.grade} · Section ${student.section}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(
              RoutePaths.of(RoutePaths.studentDetail, <String, String>{
                'studentId': student.studentId,
              }),
            ),
          );
        },
      ),
    );
  }
}

final class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.school});

  final School school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StudentsListState state = ref.watch(studentsListProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _FilterChipDropdown(
              label: 'Grade',
              value: state.grade,
              options: school.grades,
              onChanged: (String? value) =>
                  ref.read(studentsListProvider.notifier).filterByGrade(value),
            ),
            const SizedBox(width: 8),
            _FilterChipDropdown(
              label: 'Section',
              value: state.section,
              options: const <String>['A', 'B', 'C', 'D', 'E'],
              onChanged: (String? value) => ref
                  .read(studentsListProvider.notifier)
                  .filterBySection(value),
            ),
          ],
        ),
      ),
    );
  }
}

final class _FilterChipDropdown extends StatelessWidget {
  const _FilterChipDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<String?>(
    value: value,
    hint: Text(label),
    underline: const SizedBox.shrink(),
    items: <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(child: Text('All')),
      ...options.map(
        (String option) => DropdownMenuItem<String?>(
          value: option,
          child: Text(option),
        ),
      ),
    ],
    onChanged: onChanged,
  );
}
