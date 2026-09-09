/// "Start or continue an assessment": a teacher's existing sessions, and the
/// assignments they can start a new one from.
///
/// Starting a session never calls a network-backed repository — only
/// downloading an assignment's [SessionPrerequisites] does. That split is
/// what makes "download while you still have signal, then work all day in
/// airplane mode" possible (docs/06-offline-sync-strategy.md §2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_prerequisites.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  bool _isLoading = true;
  Failure? _failure;
  List<AssessmentSession> _sessions = const <AssessmentSession>[];
  List<AssessmentAssignment> _assignments = const <AssessmentAssignment>[];
  Set<String> _downloadedAssignmentIds = const <String>{};
  final Set<String> _downloadingAssignmentIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccessScope get _scope =>
      ref.read(sessionProvider).authorization.user?.scope ??
      const AccessScope(level: ScopeLevel.school);

  String get _teacherUserId =>
      ref.read(sessionProvider).authorization.user?.userId ?? '';

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _failure = null;
    });
    final scope = _scope;
    final sessionsResult = await ref
        .read(assessmentSessionsRepositoryProvider)
        .listSessions(scope: scope, teacherUserId: _teacherUserId);
    final assignmentsResult = await ref
        .read(assessmentsRepositoryProvider)
        .listAssignments(scope: scope);
    final downloadedResult = await ref
        .read(sessionPrerequisitesRepositoryProvider)
        .listDownloaded();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _failure = sessionsResult.failureOrNull ?? assignmentsResult.failureOrNull;
      _sessions = sessionsResult.valueOrNull ?? const <AssessmentSession>[];
      _assignments = assignmentsResult.valueOrNull?.items ?? const <AssessmentAssignment>[];
      _downloadedAssignmentIds = downloadedResult.valueOrNull
              ?.map((SessionPrerequisites p) => p.assignmentId)
              .toSet() ??
          const <String>{};
    });
  }

  Future<void> _download(AssessmentAssignment assignment) async {
    setState(() => _downloadingAssignmentIds.add(assignment.assignmentId));
    final result = await ref
        .read(sessionPrerequisitesDownloaderProvider)
        .download(assignment);
    if (!mounted) {
      return;
    }
    setState(() {
      _downloadingAssignmentIds.remove(assignment.assignmentId);
      if (result.isSuccess) {
        _downloadedAssignmentIds = <String>{
          ..._downloadedAssignmentIds,
          assignment.assignmentId,
        };
      } else {
        _failure = result.failureOrNull;
      }
    });
  }

  Future<void> _startSession(AssessmentAssignment assignment, String section) async {
    final prerequisitesResult = await ref
        .read(sessionPrerequisitesRepositoryProvider)
        .get(assignment.assignmentId);
    final SessionPrerequisites? prerequisites = prerequisitesResult.valueOrNull;
    if (prerequisites == null) {
      setState(
        () => _failure =
            prerequisitesResult.failureOrNull ??
            const ValidationFailure(
              userMessage: 'Download this assessment before starting a session.',
            ),
      );
      return;
    }
    final result = await ref
        .read(assessmentSessionsRepositoryProvider)
        .startSession(
          prerequisites: prerequisites,
          section: section,
          expectedStudentCount: assignment.expectedStudentCount,
          teacherUserId: _teacherUserId,
          deviceId: ref.read(deviceInfoProvider).deviceId,
        );
    if (!mounted) {
      return;
    }
    final AssessmentSession? started = result.valueOrNull;
    if (started == null) {
      setState(() => _failure = result.failureOrNull);
      return;
    }
    context.go(
      RoutePaths.of(RoutePaths.assessmentSession, <String, String>{
        'sessionId': started.sessionId,
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sessions')),
    body: SafeArea(
      child: _isLoading
          ? const LoadingView()
          : _failure != null && _sessions.isEmpty && _assignments.isEmpty
          ? FailureView(failure: _failure!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  if (_failure != null) ...<Widget>[
                    InfoBanner(
                      message: _failure!.userMessage,
                      icon: Icons.error_outline,
                      isWarning: true,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Your sessions', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_sessions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No sessions yet.'),
                    )
                  else
                    for (final AssessmentSession session in _sessions)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            session.status == SessionStatus.completed
                                ? Icons.check_circle_outline
                                : Icons.play_circle_outline,
                          ),
                          title: Text(
                            'Grade ${session.grade} · Section ${session.section}',
                          ),
                          subtitle: Text(
                            '${session.status.displayName} · '
                            '${session.studentIds.length} students',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(
                            RoutePaths.of(
                              RoutePaths.assessmentSession,
                              <String, String>{'sessionId': session.sessionId},
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 24),
                  Text('Start a new session', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_assignments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No assessments are assigned to you yet.'),
                    )
                  else
                    for (final AssessmentAssignment assignment in _assignments)
                      _AssignmentCard(
                        assignment: assignment,
                        isDownloaded: _downloadedAssignmentIds.contains(
                          assignment.assignmentId,
                        ),
                        isDownloading: _downloadingAssignmentIds.contains(
                          assignment.assignmentId,
                        ),
                        onDownload: () => _download(assignment),
                        onStartSection: (String section) =>
                            _startSession(assignment, section),
                      ),
                ],
              ),
            ),
    ),
  );
}

final class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignment,
    required this.isDownloaded,
    required this.isDownloading,
    required this.onDownload,
    required this.onStartSection,
  });

  final AssessmentAssignment assignment;
  final bool isDownloaded;
  final bool isDownloading;
  final VoidCallback onDownload;
  final ValueChanged<String> onStartSection;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Grade ${assignment.grade} · ${assignment.sections.join(', ')}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${assignment.expectedStudentCount} students expected',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (!isDownloaded)
            OutlinedButton.icon(
              onPressed: isDownloading ? null : onDownload,
              icon: isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(
                isDownloading ? 'Downloading…' : 'Download for offline',
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String section in assignment.sections)
                  FilledButton(
                    onPressed: () => onStartSection(section),
                    child: Text('Start Section $section'),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
