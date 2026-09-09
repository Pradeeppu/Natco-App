/// The answer key editor.
///
/// Two modes, and the screen never blurs them:
///
/// * **Draft** — answers are editable and nothing has been scored against
///   them yet.
/// * **Published** — read-only. The only way to change an answer is to open a
///   correction, which creates the next version with a stated reason
///   (Critical Rule 7).
///
/// The published mode is deliberately not a disabled-looking version of the
/// editor. A greyed-out grid invites people to hunt for the enable switch; a
/// screen that explains *why* it is fixed, and offers the correct action
/// instead, does not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/service/answer_key_policy.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';

final class AnswerKeyScreen extends ConsumerStatefulWidget {
  const AnswerKeyScreen({required this.assessmentId, super.key});

  final String assessmentId;

  @override
  ConsumerState<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends ConsumerState<AnswerKeyScreen> {
  AnswerKey? _draft;
  bool _loading = true;
  bool _saving = false;
  Failure? _failure;

  /// The published version, when there is one. Held alongside the draft so the
  /// screen can say what a correction would replace.
  AnswerKey? _published;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository = ref.read(assessmentRepositoryProvider);
    final Result<List<AnswerKey>> versionsResult = await repository
        .listAnswerKeyVersions(widget.assessmentId);
    if (!mounted) {
      return;
    }
    if (versionsResult.isFailure) {
      setState(() {
        _loading = false;
        _failure = versionsResult.failureOrNull;
      });
      return;
    }
    final List<AnswerKey> versions = versionsResult.valueOrNull!;
    final AnswerKey? openDraft = versions
        .where((AnswerKey k) => !k.isPublished)
        .firstOrNull;
    final AnswerKey? latestPublished = versions
        .where((AnswerKey k) => k.isPublished)
        .firstOrNull;

    if (openDraft != null) {
      setState(() {
        _loading = false;
        _draft = openDraft;
        _published = latestPublished;
      });
      return;
    }
    if (latestPublished != null) {
      // Everything is published: show it read-only. A correction is a
      // deliberate act with a reason, not something opening a screen starts.
      setState(() {
        _loading = false;
        _draft = null;
        _published = latestPublished;
      });
      return;
    }

    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    final Result<AnswerKey> created = await repository
        .getOrCreateDraftAnswerKey(
          widget.assessmentId,
          actorUserId: actor?.userId ?? '',
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      created.fold(
        onSuccess: (AnswerKey key) => _draft = key,
        onFailure: (Failure f) => _failure = f,
      );
    });
  }

  void _setAnswer(int questionNumber, String option, int totalQuestions) {
    final AnswerKey? draft = _draft;
    if (draft == null) {
      return;
    }
    final ({AnswerKey? key, Failure? failure}) result =
        AnswerKeyPolicy.setAnswer(
          draft,
          questionNumber: questionNumber,
          option: option,
          totalQuestions: totalQuestions,
        );
    if (result.failure != null) {
      setState(() => _failure = result.failure);
      return;
    }
    setState(() {
      _draft = result.key;
      _failure = null;
    });
  }

  Future<void> _save() async {
    final AnswerKey? draft = _draft;
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (draft == null || actor == null) {
      return;
    }
    setState(() => _saving = true);
    final Result<AnswerKey> result = await ref
        .read(assessmentRepositoryProvider)
        .saveDraftAnswerKey(
          draft,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      result.fold(
        onSuccess: (AnswerKey key) => _draft = key,
        onFailure: (Failure f) => _failure = f,
      );
    });
    if (result.isSuccess && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Draft saved.')));
    }
  }

  Future<void> _publish(Assessment assessment) async {
    final AnswerKey? draft = _draft;
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (draft == null || actor == null) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Publish version ${draft.version}?'),
        content: Text(
          draft.isCorrection
              ? 'Version ${draft.version} replaces version '
                    '${draft.supersedesVersion}. Results already scored '
                    'against the old version keep their history, and the '
                    'reason you gave is shown alongside any that get '
                    're-scored.'
              : 'Once published, this answer key cannot be edited. Correcting '
                    'an answer later creates version 2 with a stated reason.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }

    setState(() => _saving = true);
    final Result<AnswerKey> result = await ref
        .read(assessmentRepositoryProvider)
        .publishAnswerKey(
          draft,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      result.fold(
        onSuccess: (AnswerKey key) {
          _published = key;
          _draft = null;
          _failure = null;
        },
        onFailure: (Failure f) => _failure = f,
      );
    });
    if (result.isSuccess) {
      ref
        ..invalidate(assessmentProvider(widget.assessmentId))
        ..invalidate(answerKeyVersionsProvider(widget.assessmentId));
    }
  }

  Future<void> _startCorrection() async {
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CorrectionReasonDialog(),
    );
    if (reason == null || !mounted) {
      return;
    }

    setState(() => _saving = true);
    final Result<AnswerKey> result = await ref
        .read(assessmentRepositoryProvider)
        .startCorrection(
          widget.assessmentId,
          changeReason: reason,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      result.fold(
        onSuccess: (AnswerKey key) {
          _draft = key;
          _failure = null;
        },
        onFailure: (Failure f) => _failure = f,
      );
    });
    if (result.isSuccess) {
      ref.invalidate(answerKeyVersionsProvider(widget.assessmentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Assessment> assessmentValue = ref.watch(
      assessmentProvider(widget.assessmentId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Answer key')),
      body: SafeArea(
        child: assessmentValue.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () =>
                ref.invalidate(assessmentProvider(widget.assessmentId)),
          ),
          data: (Assessment assessment) {
            if (_loading) {
              return const LoadingView(message: 'Loading the answer key...');
            }
            final AnswerKey? draft = _draft;
            final AnswerKey? published = _published;
            if (draft == null && published == null) {
              final Failure? failure = _failure;
              return failure != null
                  ? FailureView(failure: failure, onRetry: _load)
                  : const EmptyView(
                      title: 'No answer key',
                      message: 'Nothing to show yet.',
                      icon: Icons.key_off_outlined,
                    );
            }
            return draft != null
                ? _Editor(
                    assessment: assessment,
                    draft: draft,
                    failure: _failure,
                    saving: _saving,
                    onSetAnswer: _setAnswer,
                    onSave: _save,
                    onPublish: () => _publish(assessment),
                  )
                : _PublishedView(
                    assessment: assessment,
                    key_: published!,
                    saving: _saving,
                    failure: _failure,
                    onStartCorrection: _startCorrection,
                  );
          },
        ),
      ),
    );
  }
}

/// The editable grid.
final class _Editor extends StatelessWidget {
  const _Editor({
    required this.assessment,
    required this.draft,
    required this.failure,
    required this.saving,
    required this.onSetAnswer,
    required this.onSave,
    required this.onPublish,
  });

  final Assessment assessment;
  final AnswerKey draft;
  final Failure? failure;
  final bool saving;
  final void Function(int questionNumber, String option, int total) onSetAnswer;
  final VoidCallback onSave;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<int> missing = draft.incompleteQuestions(
      assessment.totalQuestions,
    );
    final int answered = assessment.totalQuestions - missing.length;
    final Map<int, AnswerKeyEntry> byQuestion = draft.byQuestion;

    return Column(
      children: <Widget>[
        if (failure != null)
          InfoBanner(
            message: failure!.userMessage,
            icon: Icons.error_outline,
            isWarning: true,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Version ${draft.version}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  const StatusChip(label: 'Draft', tone: StatusTone.pending),
                ],
              ),
              if (draft.isCorrection && draft.changeReason != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Correcting version ${draft.supersedesVersion}: '
                  '${draft.changeReason}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              // A count, not a percentage: "43 of 50" tells you how many are
              // left; "86%" makes you work it out.
              Text(
                '$answered of ${assessment.totalQuestions} answered',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: assessment.totalQuestions == 0
                    ? 0
                    : answered / assessment.totalQuestions,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: assessment.totalQuestions,
            itemBuilder: (BuildContext context, int index) {
              final int questionNumber = index + 1;
              final String? selected =
                  byQuestion[questionNumber]?.correctOption;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 40,
                      child: Text(
                        'Q$questionNumber',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected == null
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        children: kAnswerOptions
                            .map(
                              (String option) => ChoiceChip(
                                label: Text(option),
                                selected: selected == option,
                                onSelected: (_) => onSetAnswer(
                                  questionNumber,
                                  option,
                                  assessment.totalQuestions,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : onSave,
                    child: const Text('Save draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    // Disabled while incomplete rather than failing on tap:
                    // the count above already says what is missing, so the
                    // button has nothing to add by letting you press it.
                    onPressed: saving || missing.isNotEmpty ? null : onPublish,
                    child: Text(
                      missing.isEmpty
                          ? 'Publish v${draft.version}'
                          : '${missing.length} left',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The read-only view of a published version.
final class _PublishedView extends StatelessWidget {
  const _PublishedView({
    required this.assessment,
    required AnswerKey key_,
    required this.saving,
    required this.failure,
    required this.onStartCorrection,
  }) : _key = key_;

  final Assessment assessment;
  final AnswerKey _key;
  final bool saving;
  final Failure? failure;
  final VoidCallback onStartCorrection;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        if (failure != null) ...<Widget>[
          InfoBanner(
            message: failure!.userMessage,
            icon: Icons.error_outline,
            isWarning: true,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: <Widget>[
            Text(
              'Version ${_key.version}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            const StatusChip(label: 'Published', tone: StatusTone.success),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'This version is fixed. Results scored against it stay traceable to '
          'it, which is why it cannot be edited. To change an answer, start a '
          'correction — it becomes version ${_key.version + 1} and records why.',
          style: theme.textTheme.bodyMedium,
        ),
        if (_key.changeReason != null) ...<Widget>[
          const SizedBox(height: 16),
          Text('Why this version exists', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(_key.changeReason!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: saving ? null : onStartCorrection,
          icon: const Icon(Icons.edit_note_outlined),
          label: Text('Start correction (v${_key.version + 1})'),
        ),
        const Divider(height: 32),
        Text('Answers', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int q = 1; q <= assessment.totalQuestions; q++)
              _AnswerCell(
                questionNumber: q,
                option: _key.optionFor(q),
              ),
          ],
        ),
      ],
    );
  }
}

final class _AnswerCell extends StatelessWidget {
  const _AnswerCell({required this.questionNumber, required this.option});

  final int questionNumber;

  /// `null` when the key does not cover this question — shown as a dash
  /// rather than hidden, because a hole in a published key is something
  /// somebody needs to see.
  final String? option;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            '$questionNumber',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            option ?? '-',
            style: theme.textTheme.titleMedium?.copyWith(
              color: option == null ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks why a correction is needed. The reason is required, because a
/// correction with no stated cause is indistinguishable from a mistake.
final class _CorrectionReasonDialog extends StatefulWidget {
  const _CorrectionReasonDialog();

  @override
  State<_CorrectionReasonDialog> createState() =>
      _CorrectionReasonDialogState();
}

class _CorrectionReasonDialogState extends State<_CorrectionReasonDialog> {
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
      title: const Text('Why is this correction needed?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This is shown next to every result that gets re-scored, so write '
            'it for the person who will read it months from now.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
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
          child: const Text('Start correction'),
        ),
      ],
    );
  }
}
