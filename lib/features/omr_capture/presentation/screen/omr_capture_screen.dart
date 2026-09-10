/// OMR capture: durable capture, the image-quality gate, and a link to the
/// session roster (phase 5).
///
/// Reads `sessionId` from the query string — the same convention
/// `ResultsScreen` uses for `assessmentId` — because a sheet only means
/// anything next to the session (and therefore the roster and ancestry) it
/// was captured for; `AssessmentSessionScreen`'s "Capture next OMR" button is
/// the one real entry point.
///
/// Two choices worth naming:
///
/// * There is no live camera preview here. `image_picker`'s camera source
///   hands the whole capture UI to the device's own camera app and returns a
///   file — one less custom camera lifecycle to get wrong, and the same
///   photo either way. A future iteration can build a live preview with
///   `package:camera` if framing guidance turns out to matter more than this
///   simplification costs.
/// * The OMR ID is typed by hand. Reading it off the sheet automatically is
///   phase 6's job (bubble-grid decoding); until that pipeline exists, the
///   person capturing is the only source for it.
///
/// The write order matters (Critical Rule 12): [OmrImageWriter] puts the
/// photo durably on disk *before* [OmrValidationRepository.createSubmission]
/// is ever called, so a crash between the two loses at most an unlinked
/// database row, never the evidence.
library;

import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/presentation/controller/session_controllers.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_processing/domain/service/image_quality_analyzer.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_image_writer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

final class OmrCaptureScreen extends ConsumerWidget {
  const OmrCaptureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? sessionId = GoRouterState.of(
      context,
    ).uri.queryParameters['sessionId'];

    return Scaffold(
      appBar: AppBar(title: const Text('Capture OMR')),
      body: SafeArea(
        child: sessionId == null
            ? const EmptyView(
                title: 'No session selected',
                message:
                    'Open capture from an in-progress session so the sheet '
                    'can be linked to the right student and roster.',
                icon: Icons.link_off_outlined,
              )
            : _SessionLoader(sessionId: sessionId),
      ),
    );
  }
}

final class _SessionLoader extends ConsumerWidget {
  const _SessionLoader({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AssessmentSession> session = ref.watch(
      assessmentSessionProvider(sessionId),
    );
    return session.when(
      loading: () => const LoadingView(),
      error: (Object error, StackTrace _) => FailureView(
        failure: asFailure(error),
        onRetry: () => ref.invalidate(assessmentSessionProvider(sessionId)),
      ),
      data: (AssessmentSession value) {
        if (!value.status.acceptsCapture) {
          return EmptyView(
            title: 'This session is ${value.status.displayName.toLowerCase()}',
            message: value.status == SessionStatus.ready
                ? 'Start the session before capturing sheets.'
                : 'No more sheets can be captured for it.',
            icon: Icons.block_outlined,
          );
        }
        if (value.pendingCount == 0) {
          return const EmptyView(
            title: 'Every student is accounted for',
            message: 'Nothing left on this roster to capture.',
            icon: Icons.check_circle_outline,
          );
        }
        return _CaptureBody(session: value);
      },
    );
  }
}

final class _CaptureBody extends ConsumerStatefulWidget {
  const _CaptureBody({required this.session});

  final AssessmentSession session;

  @override
  ConsumerState<_CaptureBody> createState() => _CaptureBodyState();
}

class _CaptureBodyState extends ConsumerState<_CaptureBody> {
  final TextEditingController _omrIdController = TextEditingController();
  String? _studentId;
  Uint8List? _imageBytes;
  ImageQualityReport? _quality;
  String? _overrideReason;
  bool _busy = false;

  @override
  void dispose() {
    _omrIdController.dispose();
    super.dispose();
  }

  List<SessionRosterEntry> get _pending => widget.session.roster
      .where((SessionRosterEntry e) => e.attendance == AttendanceState.pending)
      .toList(growable: false);

  bool get _canSubmit =>
      !_busy &&
      _studentId != null &&
      _omrIdController.text.trim().isNotEmpty &&
      _imageBytes != null &&
      _quality != null &&
      (_quality!.canProcess || _overrideReason != null);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Assessment> assessment = ref.watch(
      assessmentProvider(widget.session.assessmentId),
    );
    return assessment.when(
      loading: () => const LoadingView(),
      error: (Object error, StackTrace _) => FailureView(
        failure: asFailure(error),
        onRetry: () =>
            ref.invalidate(assessmentProvider(widget.session.assessmentId)),
      ),
      data: _form,
    );
  }

  Widget _form(Assessment assessment) {
    final ThemeData theme = Theme.of(context);
    final bool canOverride = ref
        .read(sessionProvider)
        .authorization
        .can(Permission.overrideQualityGate);

    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Grade ${widget.session.grade} - Section ${widget.session.section}',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${widget.session.pendingCount} student'
            '${widget.session.pendingCount == 1 ? '' : 's'} left to capture',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _studentId,
            decoration: const InputDecoration(labelText: 'Student'),
            items: _pending
                .map(
                  (SessionRosterEntry e) => DropdownMenuItem<String>(
                    value: e.studentId,
                    child: Text(e.studentName),
                  ),
                )
                .toList(growable: false),
            onChanged: _busy ? null : (String? v) => setState(() => _studentId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _omrIdController,
            decoration: const InputDecoration(
              labelText: 'OMR ID',
              helperText: 'Printed on the sheet — read it by hand for now.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          if (_imageBytes == null) ..._captureButtons() else ..._preview(theme),
          if (_quality != null) ...<Widget>[
            const SizedBox(height: 20),
            _qualityCard(theme, canOverride),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _canSubmit ? () => _submit(assessment) : null,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_busy ? 'Saving...' : 'Save capture'),
          ),
        ],
      ),
    );
  }

  List<Widget> _captureButtons() => <Widget>[
    FilledButton.icon(
      onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
      icon: const Icon(Icons.camera_alt_outlined),
      label: const Text('Capture'),
    ),
    const SizedBox(height: 10),
    OutlinedButton.icon(
      onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
      icon: const Icon(Icons.photo_library_outlined),
      label: const Text('Choose from gallery'),
    ),
  ];

  List<Widget> _preview(ThemeData theme) => <Widget>[
    ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Image.memory(_imageBytes!, fit: BoxFit.contain),
    ),
    const SizedBox(height: 10),
    OutlinedButton.icon(
      onPressed: _busy
          ? null
          : () => setState(() {
              _imageBytes = null;
              _quality = null;
              _overrideReason = null;
            }),
      icon: const Icon(Icons.refresh),
      label: const Text('Retake'),
    ),
  ];

  Widget _qualityCard(ThemeData theme, bool canOverride) {
    final ImageQualityReport quality = _quality!;
    final bool passed = quality.canProcess;
    final Color color = passed
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  passed ? Icons.check_circle_outline : Icons.error_outline,
                  color: color,
                ),
                const SizedBox(width: 10),
                Text(
                  passed ? 'Image quality: pass' : 'Image quality: fail',
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ],
            ),
            if (quality.failureReasons.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ...quality.failureReasons.map(
                (String reason) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(reason, style: theme.textTheme.bodySmall),
                ),
              ),
            ],
            if (!passed) ...<Widget>[
              const SizedBox(height: 12),
              if (_overrideReason != null)
                Text(
                  'Overridden: $_overrideReason',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                OutlinedButton(
                  onPressed: canOverride ? _confirmOverride : null,
                  child: const Text('Use anyway'),
                ),
              if (_overrideReason == null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  canOverride
                      ? 'Your role may waive the gate. The waiver is '
                            'recorded against you with a reason.'
                      : 'Only a Supervisor may waive the quality gate. '
                            'Retake the photograph instead.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmOverride() async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => const _OverrideReasonDialog(),
    );
    if (reason == null || reason.isEmpty || !mounted) {
      return;
    }
    setState(() => _overrideReason = reason);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      final ph.PermissionStatus status = await ph.Permission.camera.request();
      if (!status.isGranted) {
        _showMessage(
          'Camera permission is required to capture a sheet. Enable it in '
          'Settings.',
        );
        return;
      }
    }

    XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, imageQuality: 90);
    } catch (_) {
      _showMessage(
        source == ImageSource.camera
            ? 'Could not open the camera on this device. Try the gallery '
                  'instead.'
            : 'Could not open the gallery on this device.',
      );
      return;
    }
    if (file == null || !mounted) {
      return; // Cancelled — not an error.
    }

    final Uint8List bytes = await file.readAsBytes();
    final Result<ImageQualityReport> result = ImageQualityAnalyzer.analyze(
      imageBytes: bytes,
    );
    if (!mounted) {
      return;
    }
    result.fold(
      onSuccess: (ImageQualityReport report) => setState(() {
        _imageBytes = bytes;
        _quality = report;
        _overrideReason = null;
      }),
      onFailure: (Failure failure) => _showMessage(failure.userMessage),
    );
  }

  Future<void> _submit(Assessment assessment) async {
    final String? studentId = _studentId;
    final String omrId = _omrIdController.text.trim();
    final Uint8List? bytes = _imageBytes;
    final ImageQualityReport? quality = _quality;
    if (studentId == null || omrId.isEmpty || bytes == null || quality == null) {
      return;
    }
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }

    setState(() => _busy = true);
    try {
      // Written to disk before anything else touches it (Critical Rule 12) —
      // the evidence exists whether or not the rest of this method succeeds.
      final Directory documentsDir = await getApplicationDocumentsDirectory();
      final Result<String> written = await OmrImageWriter.writeCapturedImage(
        fileSystem: ref.read(fileSystemServiceProvider),
        documentsRootPath: documentsDir.path,
        imageBytes: bytes,
        academicYear: assessment.academicYear,
        assessmentId: widget.session.assessmentId,
        stateId: widget.session.stateId,
        districtId: widget.session.districtId,
        clusterId: widget.session.clusterId,
        schoolId: widget.session.schoolId,
        capturedAt: DateTime.now(),
        omrId: omrId,
      );
      if (written.isFailure) {
        _showMessage(written.failureOrNull!.userMessage);
        return;
      }

      final Result<OmrSubmission> created = await ref
          .read(omrValidationRepositoryProvider)
          .createSubmission(
            omrId: omrId,
            sessionId: widget.session.sessionId,
            assessmentId: widget.session.assessmentId,
            studentId: studentId,
            schoolId: widget.session.schoolId,
            clusterId: widget.session.clusterId,
            districtId: widget.session.districtId,
            stateId: widget.session.stateId,
            capturedBy: actor.userId,
            actorRole: actor.role.wireName,
            originalImagePath: written.valueOrNull!,
            imageQuality: quality,
            qualityOverrideBy: _overrideReason == null ? null : actor.userId,
            qualityOverrideReason: _overrideReason,
          );
      if (created.isFailure) {
        // The image is still safely on disk even though this row was
        // refused (most likely a re-used OMR ID) — nothing is lost, the
        // capturer just needs to correct the ID and save again.
        _showMessage(created.failureOrNull!.userMessage);
        return;
      }

      final Result<AssessmentSession> attached = await ref
          .read(sessionRepositoryProvider)
          .attachOmr(
            widget.session.sessionId,
            studentId: studentId,
            omrId: omrId,
            actorUserId: actor.userId,
            actorRole: actor.role.wireName,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(assessmentSessionProvider(widget.session.sessionId));
      attached.fold(
        onSuccess: (_) => _showMessage('Captured. Ready for the next student.'),
        onFailure: (Failure failure) => _showMessage(
          'Captured, but the roster could not be updated: '
          '${failure.userMessage}',
        ),
      );
      setState(() {
        _studentId = null;
        _omrIdController.clear();
        _imageBytes = null;
        _quality = null;
        _overrideReason = null;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

final class _OverrideReasonDialog extends StatefulWidget {
  const _OverrideReasonDialog();

  @override
  State<_OverrideReasonDialog> createState() => _OverrideReasonDialogState();
}

class _OverrideReasonDialogState extends State<_OverrideReasonDialog> {
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
      title: const Text('Use this sheet anyway?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This sheet failed the image-quality gate. Waiving it is '
            'recorded against you with the reason below.',
          ),
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
          child: const Text('Use anyway'),
        ),
      ],
    );
  }
}
