/// A live assessment session for one school, grade and section.
///
/// Deliberately outside the shell (see `GuardedRoute.insideShell`'s doc
/// comment): a live session is a full-screen task, and a teacher should not
/// be able to wander off mid-session by tapping the navigation bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/session_status.dart';
import 'package:natco_app/features/assessment_sessions/presentation/controller/session_controller.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';

final class AssessmentSessionScreen extends ConsumerStatefulWidget {
  const AssessmentSessionScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<AssessmentSessionScreen> createState() =>
      _AssessmentSessionScreenState();
}

class _AssessmentSessionScreenState
    extends ConsumerState<AssessmentSessionScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref
          .read(sessionControllerProvider.notifier)
          .viewSession(widget.sessionId),
    );
  }

  Future<void> _confirmEndSession() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('End session?'),
        content: const Text(
          'This closes the session for everyone. You cannot resume it '
          'afterwards.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(sessionControllerProvider.notifier).endSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionDetailState state = ref.watch(sessionControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        leading: state.session?.status == SessionStatus.completed
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.go('/dashboard'),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: state.isLoading && state.session == null
            ? const LoadingView()
            : state.failure != null && state.session == null
            ? FailureView(
                failure: state.failure!,
                onRetry: () => ref
                    .read(sessionControllerProvider.notifier)
                    .viewSession(widget.sessionId),
              )
            : state.session == null
            ? const EmptyView(
                title: 'Session not found',
                icon: Icons.play_circle_outline,
              )
            : _SessionBody(
                session: state.session!,
                failure: state.failure,
                onEndSession: _confirmEndSession,
              ),
      ),
    );
  }
}

/// Submissions captured for one session so far.
final capturedSubmissionsProvider =
    FutureProvider.family<List<OmrSubmission>, String>((Ref ref, String sessionId) async {
      final result = await ref
          .read(omrSubmissionsRepositoryProvider)
          .listForSession(sessionId);
      return result.valueOrNull ?? const <OmrSubmission>[];
    });

final class _SessionBody extends ConsumerWidget {
  const _SessionBody({
    required this.session,
    required this.failure,
    required this.onEndSession,
  });

  final AssessmentSession session;
  final Failure? failure;
  final VoidCallback onEndSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool isCompleted = session.status == SessionStatus.completed;
    final authorization = ref.watch(sessionProvider).authorization;
    final bool canCapture = authorization.can(Permission.captureOmr);
    final bool canReview = authorization.can(Permission.reviewScanQuality);
    final AsyncValue<List<OmrSubmission>> captured = ref.watch(
      capturedSubmissionsProvider(session.sessionId),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        if (failure != null) ...<Widget>[
          InfoBanner(
            message: failure!.userMessage,
            icon: Icons.error_outline,
            isWarning: true,
          ),
          const SizedBox(height: 16),
        ],
        Icon(
          isCompleted ? Icons.check_circle_outline : Icons.play_circle_outline,
          size: 56,
          color: isCompleted ? Colors.green : theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Grade ${session.grade} · Section ${session.section}',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        Text(
          '${session.subject} · ${session.academicYear}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Center(child: Chip(label: Text(session.status.displayName))),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                _StatRow(
                  label: 'Students on roster',
                  value: '${session.studentIds.length}',
                ),
                _StatRow(
                  label: 'Expected',
                  value: '${session.expectedStudentCount}',
                ),
                if (session.startedAt != null)
                  _StatRow(
                    label: 'Started',
                    value: _formatTime(session.startedAt!),
                  ),
                if (session.endedAt != null)
                  _StatRow(
                    label: 'Ended',
                    value: _formatTime(session.endedAt!),
                  ),
                _StatRow(
                  label: 'Sheets captured',
                  value: '${captured.value?.length ?? 0}',
                ),
              ],
            ),
          ),
        ),
        if (canReview && (captured.value?.isNotEmpty ?? false)) ...<Widget>[
          const SizedBox(height: 20),
          Text('Captured sheets', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final OmrSubmission submission in captured.value!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Sheet ${submission.omrId}'),
                subtitle: Text(submission.processingStatus.wireName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  RoutePaths.of(RoutePaths.omrReview, <String, String>{
                    'omrId': submission.omrId,
                  }),
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        if (isCompleted)
          const Text(
            'This session is complete.',
            textAlign: TextAlign.center,
          )
        else ...<Widget>[
          const Text(
            'Running entirely on this device — no connection is needed to '
            'capture sheets or end the session.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (canCapture) ...<Widget>[
            FilledButton.icon(
              onPressed: () async {
                await context.push(
                  Uri(
                    path: RoutePaths.omrCapture,
                    queryParameters: <String, String>{
                      'sessionId': session.sessionId,
                    },
                  ).toString(),
                );
                ref.invalidate(capturedSubmissionsProvider(session.sessionId));
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Capture OMR'),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: onEndSession,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('End session'),
          ),
        ],
      ],
    );
  }

  static String _formatTime(DateTime time) {
    final DateTime local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}

final class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
