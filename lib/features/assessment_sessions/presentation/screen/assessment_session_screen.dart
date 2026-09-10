/// A live assessment session: the teacher's working screen.
///
/// This is the screen a teacher holds while standing in front of a class, so
/// the next action and the count of what is left sit above everything else.
/// Layout comes before polish here on purpose (docs/01-architecture.md's
/// priority table): a teacher glancing at this between students needs the
/// count, not the chrome.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/presentation/controller/session_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';

final class AssessmentSessionScreen extends ConsumerWidget {
  const AssessmentSessionScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AssessmentSession> value = ref.watch(
      assessmentSessionProvider(sessionId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: SafeArea(
        child: value.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () =>
                ref.invalidate(assessmentSessionProvider(sessionId)),
          ),
          data: (AssessmentSession session) => _Body(session: session),
        ),
      ),
    );
  }
}

final class _Body extends ConsumerWidget {
  const _Body({required this.session});

  final AssessmentSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Grade ${session.grade} - Section ${session.section}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    StatusChip(
                      label: session.status.displayName,
                      tone: switch (session.status) {
                        SessionStatus.ready => StatusTone.pending,
                        SessionStatus.inProgress => StatusTone.success,
                        SessionStatus.completed => StatusTone.neutral,
                        SessionStatus.abandoned => StatusTone.danger,
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: session.totalStudents == 0
                      ? 0
                      : session.capturedCount / session.totalStudents,
                  color: status.success,
                  minHeight: 10,
                ),
                const SizedBox(height: 10),
                Text(
                  '${session.capturedCount} of ${session.totalStudents} '
                  'students captured - ${session.pendingCount} left'
                  '${session.absentCount > 0 ? ", ${session.absentCount} absent" : ""}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        if (session.status == SessionStatus.abandoned &&
            session.abandonReason != null) ...<Widget>[
          const SizedBox(height: 12),
          InfoBanner(
            message: 'Abandoned: ${session.abandonReason}',
            icon: Icons.flag_outlined,
            isWarning: true,
          ),
        ],
        const SizedBox(height: 16),
        if (session.status == SessionStatus.ready)
          FilledButton.icon(
            onPressed: () => _changeStatus(context, ref, SessionStatus.inProgress),
            icon: const Icon(Icons.play_arrow_outlined),
            label: const Text('Start session'),
          )
        else if (session.status.acceptsCapture)
          FilledButton.icon(
            onPressed: () => context.push(
              '${RoutePaths.omrCapture}?sessionId=${session.sessionId}',
            ),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Capture next OMR'),
          ),
        if (session.status.acceptsCapture) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: session.isFullyAccountedFor
                      ? () => _changeStatus(context, ref, SessionStatus.completed)
                      : null,
                  child: Text(
                    session.isFullyAccountedFor
                        ? 'Complete session'
                        : '${session.pendingCount} left to account for',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => _confirmAbandon(context, ref),
                child: const Text('Abandon'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text('Roster', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Downloaded before the session, so it renders with no connection.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: session.roster
                .map(
                  (SessionRosterEntry entry) => _RosterTile(
                    session: session,
                    entry: entry,
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    SessionStatus next,
  ) async {
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }
    final Result<AssessmentSession> result = await ref
        .read(sessionRepositoryProvider)
        .changeStatus(
          session.sessionId,
          next: next,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!context.mounted) {
      return;
    }
    result.fold(
      onSuccess: (_) =>
          ref.invalidate(assessmentSessionProvider(session.sessionId)),
      onFailure: (Failure failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.userMessage))),
    );
  }

  Future<void> _confirmAbandon(BuildContext context, WidgetRef ref) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => const _AbandonReasonDialog(),
    );
    if (reason == null || !context.mounted) {
      return;
    }
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }
    final Result<AssessmentSession> result = await ref
        .read(sessionRepositoryProvider)
        .changeStatus(
          session.sessionId,
          next: SessionStatus.abandoned,
          reason: reason,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!context.mounted) {
      return;
    }
    result.fold(
      onSuccess: (_) =>
          ref.invalidate(assessmentSessionProvider(session.sessionId)),
      onFailure: (Failure failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.userMessage))),
    );
  }
}

final class _RosterTile extends ConsumerWidget {
  const _RosterTile({required this.session, required this.entry});

  final AssessmentSession session;
  final SessionRosterEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool canMarkAbsent =
        session.status.acceptsCapture &&
        entry.attendance != AttendanceState.captured;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Text(
          entry.studentName.isEmpty ? '?' : entry.studentName[0],
          style: theme.textTheme.bodySmall,
        ),
      ),
      title: Text(entry.studentName),
      subtitle: entry.absenceNote != null ? Text(entry.absenceNote!) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          switch (entry.attendance) {
            AttendanceState.captured => const StatusChip(
              label: 'Captured',
              tone: StatusTone.success,
            ),
            AttendanceState.absent => const StatusChip(
              label: 'Absent',
              tone: StatusTone.neutral,
            ),
            AttendanceState.pending => const StatusChip(
              label: 'Not captured',
              tone: StatusTone.pending,
            ),
          },
          if (canMarkAbsent)
            IconButton(
              icon: const Icon(Icons.person_off_outlined, size: 20),
              tooltip: 'Mark absent',
              onPressed: () => _markAbsent(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _markAbsent(BuildContext context, WidgetRef ref) async {
    final String? note = await showDialog<String>(
      context: context,
      builder: (_) => _AbsenceNoteDialog(studentName: entry.studentName),
    );
    if (note == null || !context.mounted) {
      return;
    }
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }
    final Result<AssessmentSession> result = await ref
        .read(sessionRepositoryProvider)
        .setAttendance(
          session.sessionId,
          studentId: entry.studentId,
          attendance: AttendanceState.absent,
          note: note.isEmpty ? null : note,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!context.mounted) {
      return;
    }
    result.fold(
      onSuccess: (_) =>
          ref.invalidate(assessmentSessionProvider(session.sessionId)),
      onFailure: (Failure failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.userMessage))),
    );
  }
}

final class _AbsenceNoteDialog extends StatefulWidget {
  const _AbsenceNoteDialog({required this.studentName});

  final String studentName;

  @override
  State<_AbsenceNoteDialog> createState() => _AbsenceNoteDialogState();
}

class _AbsenceNoteDialogState extends State<_AbsenceNoteDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mark ${widget.studentName} absent?'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Note (optional)'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Mark absent'),
        ),
      ],
    );
  }
}

final class _AbandonReasonDialog extends StatefulWidget {
  const _AbandonReasonDialog();

  @override
  State<_AbandonReasonDialog> createState() => _AbandonReasonDialogState();
}

class _AbandonReasonDialogState extends State<_AbandonReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _touched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool empty = _controller.text.trim().isEmpty;
    return AlertDialog(
      title: const Text('Abandon this session?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Sheets already captured are kept either way.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Reason',
              errorText: _touched && empty ? 'Enter a reason.' : null,
            ),
            onChanged: (_) => setState(() => _touched = true),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: empty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Abandon'),
        ),
      ],
    );
  }
}
