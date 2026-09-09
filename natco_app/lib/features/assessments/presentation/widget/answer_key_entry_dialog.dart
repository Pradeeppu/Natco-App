/// Publish or correct an answer key.
///
/// Answers are entered as one option letter per question, in order,
/// comma-separated — `A,B,C,D,A` for a 5-question key — parsed by
/// [AnswerKeyParser] before anything reaches the repository, the same
/// two-stage "parse, then persist" shape `CsvImportDialog` uses for
/// students.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/features/assessments/domain/service/answer_key_parser.dart';

/// Shows the dialog. [existingAnswers] pre-fills the field with the current
/// published key's answers, in question-number order, for a correction; pass
/// an empty map for a fresh key. [isCorrection] gates the change-reason
/// field.
Future<void> showAnswerKeyEntryDialog({
  required BuildContext context,
  required int questionCount,
  required List<String> options,
  required Map<int, String> existingAnswers,
  required bool isCorrection,
  required Future<Failure?> Function(
    Map<int, String> answers,
    String? changeReason,
  )
  onSubmit,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => _AnswerKeyEntryDialog(
    questionCount: questionCount,
    options: options,
    existingAnswers: existingAnswers,
    isCorrection: isCorrection,
    onSubmit: onSubmit,
  ),
);

final class _AnswerKeyEntryDialog extends StatefulWidget {
  const _AnswerKeyEntryDialog({
    required this.questionCount,
    required this.options,
    required this.existingAnswers,
    required this.isCorrection,
    required this.onSubmit,
  });

  final int questionCount;
  final List<String> options;
  final Map<int, String> existingAnswers;
  final bool isCorrection;
  final Future<Failure?> Function(
    Map<int, String> answers,
    String? changeReason,
  )
  onSubmit;

  @override
  State<_AnswerKeyEntryDialog> createState() => _AnswerKeyEntryDialogState();
}

class _AnswerKeyEntryDialogState extends State<_AnswerKeyEntryDialog> {
  late final TextEditingController _answersController;
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  Failure? _failure;
  List<AnswerKeyParseError> _parseErrors = const <AnswerKeyParseError>[];

  @override
  void initState() {
    super.initState();
    _answersController = TextEditingController(
      text: <String>[
        for (int n = 1; n <= widget.questionCount; n++)
          widget.existingAnswers[n] ?? '',
      ].join(','),
    );
  }

  @override
  void dispose() {
    _answersController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    const AnswerKeyParser parser = AnswerKeyParser();
    final AnswerKeyParseResult parsed = parser.parse(
      _answersController.text,
      questionCount: widget.questionCount,
      options: widget.options,
    );
    if (!parsed.isValid) {
      setState(() {
        _parseErrors = parsed.errors;
        _failure = null;
      });
      return;
    }
    if (widget.isCorrection && _reasonController.text.trim().isEmpty) {
      setState(() {
        _parseErrors = const <AnswerKeyParseError>[
          AnswerKeyParseError(
            questionNumber: 0,
            reason: 'a reason is required to correct a published key',
          ),
        ];
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _failure = null;
      _parseErrors = const <AnswerKeyParseError>[];
    });
    final Failure? failure = await widget.onSubmit(
      parsed.answers,
      widget.isCorrection ? _reasonController.text.trim() : null,
    );
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _isSubmitting = false;
        _failure = failure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isCorrection ? 'Correct answer key' : 'Publish answer key'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.isCorrection)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Publishing this will supersede the current version. Old '
                'results stay attached to the version they were scored '
                'against.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          if (_failure != null) ...<Widget>[
            Text(
              _failure!.userMessage,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _answersController,
            enabled: !_isSubmitting,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Answers (${widget.questionCount} questions)',
              helperText: 'One option per question, comma-separated, e.g. '
                  '${widget.options.take(4).join(',')},...',
            ),
          ),
          if (widget.isCorrection) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              enabled: !_isSubmitting,
              decoration: const InputDecoration(labelText: 'Reason for change'),
            ),
          ],
          if (_parseErrors.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            for (final AnswerKeyParseError error in _parseErrors)
              Text(
                error.questionNumber == 0
                    ? error.reason
                    : 'Question ${error.questionNumber}: ${error.reason}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
          ],
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(widget.isCorrection ? 'Publish correction' : 'Publish'),
      ),
    ],
  );
}
