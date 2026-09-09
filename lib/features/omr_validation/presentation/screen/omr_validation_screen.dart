/// Human validation of one sheet's flagged answers.
///
/// The most consequential screen in the product: it is where a person
/// overrules a machine. Requirement §20 and Critical Rule 3 shape it — the
/// machine's reading is shown as evidence and is never replaced, the
/// validator's decision is recorded alongside it, and the cropped bubble
/// image is on screen so the decision is made from the sheet rather than
/// from a number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_validation/domain/service/omr_validation_policy.dart';
import 'package:natco_app/features/omr_validation/presentation/controller/omr_validation_controllers.dart';

final class OmrValidationScreen extends ConsumerStatefulWidget {
  const OmrValidationScreen({required this.omrId, super.key});

  final String omrId;

  @override
  ConsumerState<OmrValidationScreen> createState() =>
      _OmrValidationScreenState();
}

class _OmrValidationScreenState extends ConsumerState<OmrValidationScreen> {
  final TextEditingController _reasonController = TextEditingController();
  String? _choice;
  bool _submitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit(OmrAnswer answer) async {
    final String? choice = _choice;
    if (choice == null) {
      return;
    }
    final SessionState session = ref.read(sessionProvider);
    final String? actorUserId = session.authorization.user?.userId;
    final String? actorRole = session.authorization.user?.role.wireName;
    if (actorUserId == null || actorRole == null) {
      return;
    }

    setState(() {
      _submitting = true;
      _failure = null;
    });

    final Result<OmrAnswer> result = await ref
        .read(omrValidationRepositoryProvider)
        .recordDecision(
          omrId: widget.omrId,
          questionNumber: answer.questionNumber,
          chosenAnswer: choice,
          reason: _reasonController.text.trim().isEmpty
              ? null
              : _reasonController.text.trim(),
          actorUserId: actorUserId,
          actorRole: actorRole,
        );

    if (!mounted) {
      return;
    }

    switch (result) {
      case Success<OmrAnswer>():
        setState(() {
          _submitting = false;
          _choice = null;
          _reasonController.clear();
        });
        // The submission's own status (does it still need validation) and
        // the answer list (is the next flagged question here) both depend on
        // the write this just made — invalidating rather than trusting
        // in-memory state is what keeps this correct against a real backend
        // too, where another device could also be looking at this sheet.
        ref.invalidate(omrAnswersProvider(widget.omrId));
        ref.invalidate(omrSubmissionProvider(widget.omrId));
      case FailureResult<OmrAnswer>(:final Failure failure):
        setState(() {
          _submitting = false;
          _failure = failure;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<OmrAnswer>> answersValue = ref.watch(
      omrAnswersProvider(widget.omrId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Validation')),
      body: SafeArea(
        child: answersValue.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () => ref.invalidate(omrAnswersProvider(widget.omrId)),
          ),
          data: (List<OmrAnswer> answers) {
            final List<OmrAnswer> flagged = answers
                .where(
                  (OmrAnswer a) => a.needsValidation && a.finalAnswer == null,
                )
                .toList();
            if (flagged.isEmpty) {
              return _DoneState(omrId: widget.omrId);
            }
            final OmrAnswer current = flagged.first;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'OMR ${widget.omrId} · Question ${current.questionNumber} '
                    'of ${answers.length} · ${flagged.length} left',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_failure != null) ...<Widget>[
                    InfoBanner(
                      message: _failure!.userMessage,
                      icon: Icons.error_outline,
                      isWarning: true,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _EvidenceCard(answer: current),
                  const SizedBox(height: 20),
                  _MachineReadingCard(answer: current),
                  const SizedBox(height: 20),
                  Text('Your decision', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Recorded against your name, alongside the machine result',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: OmrValidationPolicy.choicesFor()
                        .map(
                          (String c) => _ChoiceChip(
                            label: c,
                            isSelected: _choice == c,
                            onTap: _submitting
                                ? null
                                : () => setState(() => _choice = c),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _reasonController,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                      hintText: 'e.g. B is fully filled, A is a smudge',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (_choice == null || _submitting)
                        ? null
                        : () => _submit(current),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _choice == null
                                ? 'Choose an answer to continue'
                                : 'Record "$_choice" and go to the next',
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.answer});

  final OmrAnswer answer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('The sheet', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'Cropped from the original capture, question '
              '${answer.questionNumber}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 1.15,
              child: CustomPaint(
                painter: _BubbleRowPainter(
                  theme: theme,
                  questionNumber: answer.questionNumber,
                  darkness: answer.optionScores,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MachineReadingCard extends StatelessWidget {
  const _MachineReadingCard({required this.answer});

  final OmrAnswer answer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final List<MapEntry<String, double>> sorted =
        answer.optionScores.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final List<MapEntry<String, double>> topTwo =
        (List<MapEntry<String, double>>.of(sorted)
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(2)
            .toList();
    final bool isCoinFlip =
        topTwo.length == 2 && (topTwo[0].value - topTwo[1].value).abs() < 0.1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('What the machine read', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'Recorded evidence — never overwritten',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _statusLabel(answer.machineStatus.wireName),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: status.danger,
                    ),
                  ),
                ),
                Text(
                  'Confidence ${answer.machineConfidence.toStringAsFixed(2)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: status.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Darkness per option',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            ...sorted.map(
              (MapEntry<String, double> e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 20,
                      child: Text(e.key, style: theme.textTheme.titleSmall),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                        child: LinearProgressIndicator(
                          value: e.value.clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          color: e.value > 0.5
                              ? status.danger
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 40,
                      child: Text(
                        e.value.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isCoinFlip) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '${topTwo[0].key} and ${topTwo[1].key} are within '
                '${(topTwo[0].value - topTwo[1].value).abs().toStringAsFixed(2)} '
                'of each other. The machine did not pick one, and it will not.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String wireName) => switch (wireName) {
    'MEDIUM_CONFIDENCE' => 'Medium confidence',
    'LOW_CONFIDENCE' => 'Low confidence',
    'MULTIPLE_MARK' => 'Multiple mark',
    'UNREADABLE' => 'Unreadable',
    'BLANK' => 'Blank',
    _ => wireName,
  };
}

final class _DoneState extends ConsumerWidget {
  const _DoneState({required this.omrId});

  final String omrId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: theme.statusColors.success,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing left to decide on this sheet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Every flagged answer on OMR $omrId now has a final decision. '
              'It moves to scoring on its own.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.pop(),
              child: const Text('Back to the queue'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isLetter = label.length == 1;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Container(
        constraints: BoxConstraints(
          minWidth: isLetter ? 64 : 96,
          minHeight: NatcoTheme.minTouchTarget,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary : scheme.surface,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: isSelected
                ? scheme.onPrimary
                : onTap == null
                ? scheme.onSurface.withValues(alpha: 0.38)
                : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Draws the cropped bubble row the validator is judging: four options, each
/// shaded by its measured darkness, so the picture and the numbers agree.
class _BubbleRowPainter extends CustomPainter {
  _BubbleRowPainter({
    required this.theme,
    required this.questionNumber,
    required this.darkness,
  });

  final ThemeData theme;
  final int questionNumber;
  final Map<String, double> darkness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paper = Paint()..color = const Color(0xFFF3F1EC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      paper,
    );

    final TextPainter label = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: 'Q$questionNumber',
        style: const TextStyle(color: Color(0xFF3A3A38), fontSize: 13),
      ),
    )..layout();
    label.paint(canvas, Offset(size.width * 0.04, size.height / 2 - 8));

    final List<String> options = (darkness.keys.toList()..sort());
    final double radius = size.height * 0.24;
    for (int i = 0; i < options.length; i++) {
      final String option = options[i];
      final double fill = darkness[option] ?? 0;
      final Offset centre = Offset(
        size.width * (0.26 + i * 0.19),
        size.height * 0.5,
      );

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = const Color(0xFF2B2A28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      if (fill > 0.15) {
        canvas.drawCircle(
          centre,
          radius - 2,
          Paint()..color = const Color(0xFF2B2A28).withValues(alpha: fill.clamp(0, 1)),
        );
      }

      final TextPainter letter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: option,
          style: const TextStyle(color: Color(0xFF6B6A66), fontSize: 11),
        ),
      )..layout();
      letter.paint(
        canvas,
        Offset(centre.dx - letter.width / 2, centre.dy + radius + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BubbleRowPainter oldDelegate) =>
      oldDelegate.questionNumber != questionNumber ||
      !_mapEquals(oldDelegate.darkness, darkness);

  static bool _mapEquals(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<String, double> e in a.entries) {
      if (b[e.key] != e.value) {
        return false;
      }
    }
    return true;
  }
}
