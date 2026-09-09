/// Students: paginated, searchable, scope-filtered list, with an optional
/// school filter and (Super Admin) manual add and CSV import.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/presentation/widget/school_picker.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/presentation/controller/student_list_controller.dart';

final class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  School? _schoolFilter;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  void _ensureInitialFilter(BuildContext context) {
    if (_initialised) {
      return;
    }
    _initialised = true;
    final String? schoolId = GoRouterState.of(
      context,
    ).uri.queryParameters['schoolId'];
    if (schoolId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final Result<School> result = await ref
          .read(schoolHierarchyRepositoryProvider)
          .getSchool(schoolId);
      if (!mounted || result.isFailure) {
        return;
      }
      setState(() => _schoolFilter = result.valueOrNull);
      ref
          .read(studentListControllerProvider.notifier)
          .setSchoolFilter(schoolId);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(studentListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialFilter(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canImport = session.authorization.can(Permission.importStudents);
    final bool canAdd = session.authorization.can(Permission.manageStudents);
    final AsyncValue<PagedListState<Student>> value = ref.watch(
      studentListControllerProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
        actions: <Widget>[
          if (canImport)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Import CSV',
              onPressed: () => context.push(RoutePaths.studentImport),
            ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => context.push(RoutePaths.studentNew),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add student'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search by name',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (String q) => ref
                    .read(studentListControllerProvider.notifier)
                    .setQuery(q),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SchoolPicker(
                      label: 'Filter by school (optional)',
                      initialSchoolId: _schoolFilter?.schoolId,
                      onSelected: (School school) {
                        setState(() => _schoolFilter = school);
                        ref
                            .read(studentListControllerProvider.notifier)
                            .setSchoolFilter(school.schoolId);
                      },
                    ),
                  ),
                  if (_schoolFilter != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear school filter',
                      onPressed: () {
                        setState(() => _schoolFilter = null);
                        ref
                            .read(studentListControllerProvider.notifier)
                            .setSchoolFilter(null);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: value.when(
                loading: () => const LoadingView(),
                error: (Object error, StackTrace _) => FailureView(
                  failure: asFailure(error),
                  onRetry: () => ref
                      .read(studentListControllerProvider.notifier)
                      .refresh(),
                ),
                data: (PagedListState<Student> state) {
                  final Failure? failure = state.failure;
                  if (failure != null) {
                    return FailureView(
                      failure: failure,
                      onRetry: () => ref
                          .read(studentListControllerProvider.notifier)
                          .refresh(),
                    );
                  }
                  if (state.items.isEmpty) {
                    return const EmptyView(
                      title: 'No students found',
                      message: 'Try a different search, or add a student.',
                      icon: Icons.groups_outlined,
                    );
                  }
                  return ListView.separated(
                    controller: _scrollController,
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        );
                      }
                      final Student student = state.items[index];
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(student.studentName),
                        subtitle: Text(
                          'Grade ${student.grade} - Section ${student.section}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          RoutePaths.of(RoutePaths.studentDetail, <String, String>{
                            'studentId': student.studentId,
                          }),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
