/// Capture one OMR sheet for a live session.
///
/// The durability invariant this screen exists to uphold
/// (docs/06-offline-sync-strategy.md §1): the photo is written to durable
/// local storage the moment it is picked, before quality analysis or
/// anything else runs. A submission *record* is only created once the
/// outcome is known — pass, or an explicit "Use Anyway" — so a `Retake`
/// leaves an orphaned but harmless file rather than a half-finished record.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/quality_override.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';

final class OmrCaptureScreen extends ConsumerStatefulWidget {
  const OmrCaptureScreen({required this.sessionId, super.key});

  /// `null` when this screen was reached with no session in context (for
  /// instance, the bottom navigation bar's own "OMR" destination) — a sheet
  /// cannot be attributed to a session without one, so the screen asks the
  /// operator to start or resume a session first rather than guessing.
  final String? sessionId;

  @override
  ConsumerState<OmrCaptureScreen> createState() => _OmrCaptureScreenState();
}

enum _Step { loading, identify, reviewing, error, noSession }

class _OmrCaptureScreenState extends ConsumerState<OmrCaptureScreen> {
  _Step _step = _Step.loading;
  Failure? _loadFailure;
  AssessmentSession? _session;
  List<Student> _roster = const <Student>[];

  String? _selectedStudentId;
  final TextEditingController _omrIdController = TextEditingController();

  bool _isBusy = false;
  String? _writtenImagePath;
  ImageQualityReport? _qualityReport;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _omrIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String? sessionId = widget.sessionId;
    if (sessionId == null) {
      setState(() => _step = _Step.noSession);
      return;
    }
    final sessionResult = await ref
        .read(assessmentSessionsRepositoryProvider)
        .getSession(sessionId);
    final AssessmentSession? session = sessionResult.valueOrNull;
    if (session == null) {
      setState(() {
        _step = _Step.error;
        _loadFailure = sessionResult.failureOrNull;
      });
      return;
    }
    final rosterResult = await ref
        .read(studentsRepositoryProvider)
        .listStudents(
          scope: const AccessScope.global(),
          schoolId: session.schoolId,
          grade: session.grade,
          section: session.section,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _session = session;
      _roster = rosterResult.valueOrNull?.items
              .where((Student s) => session.studentIds.contains(s.studentId))
              .toList(growable: false) ??
          const <Student>[];
      _step = _Step.identify;
    });
  }

  Future<void> _capture(Future<Uint8List?> Function() pick) async {
    setState(() => _isBusy = true);
    final Uint8List? bytes = await pick();
    if (!mounted) {
      return;
    }
    if (bytes == null) {
      setState(() => _isBusy = false);
      return;
    }

    final String submissionId = ref.read(idGeneratorProvider).newId();
    final writeResult = await ref
        .read(omrImageStoreProvider)
        .writeOriginal(submissionId: submissionId, bytes: bytes);
    if (!mounted) {
      return;
    }
    if (writeResult.failureOrNull != null) {
      setState(() {
        _isBusy = false;
        _loadFailure = writeResult.failureOrNull;
      });
      return;
    }

    final appConfig = ref.read(appConfigProvider);
    final qualityResult = ref
        .read(imageQualityAnalyzerProvider)
        .analyse(bytes, thresholds: appConfig.scannerThresholds.imageQuality);
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _writtenImagePath = writeResult.valueOrNull;
      _qualityReport = qualityResult.valueOrNull;
      _loadFailure = qualityResult.failureOrNull;
      _step = _Step.reviewing;
    });
  }

  void _retake() {
    setState(() {
      _writtenImagePath = null;
      _qualityReport = null;
      _step = _Step.identify;
    });
  }

  Future<void> _saveSubmission({QualityOverride? override}) async {
    final AssessmentSession session = _session!;
    final ImageQualityReport report = _qualityReport!;
    final String submissionId = ref.read(idGeneratorProvider).newId();
    final String userId =
        ref.read(sessionProvider).authorization.user?.userId ?? 'unknown';
    final now = ref.read(clockProvider).nowUtc();

    final OmrSubmission draft = OmrSubmission(
      submissionId: submissionId,
      omrId: _omrIdController.text.trim(),
      sessionId: session.sessionId,
      assessmentId: session.assessmentId,
      studentId: _selectedStudentId,
      schoolId: session.schoolId,
      clusterId: session.clusterId,
      districtId: session.districtId,
      stateId: session.stateId,
      capturedBy: userId,
      capturedAt: now,
      deviceId: ref.read(deviceInfoProvider).deviceId,
      originalImagePath: _writtenImagePath!,
      imageQuality: report,
      qualityOverride: override,
      processingStatus: override != null
          ? OmrProcessingStatus.qualityFailed
          : OmrProcessingStatus.qualityChecked,
      validationStatus: ValidationStatus.notRequired,
      createdAt: now,
      updatedAt: now,
    );

    final repository = ref.read(omrSubmissionsRepositoryProvider);
    final result = override == null
        ? await repository.createSubmission(draft)
        : await (() async {
            final created = await repository.createSubmission(draft);
            if (created.isFailure) {
              return created;
            }
            return repository.overrideQualityGate(submissionId, override);
          })();

    if (!mounted) {
      return;
    }
    if (result.failureOrNull != null) {
      setState(() => _loadFailure = result.failureOrNull);
      return;
    }
    setState(() {
      _savedCount++;
      _writtenImagePath = null;
      _qualityReport = null;
      _omrIdController.clear();
      _selectedStudentId = null;
      _step = _Step.identify;
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sheet saved.')));
    }
  }

  Future<void> _useAnyway() async {
    final authorization = ref.read(sessionProvider).authorization;
    if (!authorization.can(Permission.overrideQualityGate)) {
      return;
    }
    final TextEditingController reasonController = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => ListenableBuilder(
        listenable: reasonController,
        builder: (BuildContext context, Widget? _) => AlertDialog(
          title: const Text('Use this photo anyway?'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: reasonController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(reasonController.text.trim()),
              child: const Text('Use Anyway'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) {
      return;
    }
    final String userId =
        ref.read(sessionProvider).authorization.user?.userId ?? 'unknown';
    await _saveSubmission(
      override: QualityOverride(
        overriddenBy: userId,
        reason: reason,
        overriddenAt: ref.read(clockProvider).nowUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authorization = ref.watch(sessionProvider).authorization;
    return Scaffold(
      appBar: AppBar(
        title: Text(_savedCount == 0 ? 'Capture OMR' : 'Capture OMR ($_savedCount saved)'),
      ),
      body: SafeArea(
        child: switch (_step) {
          _Step.loading => const LoadingView(),
          _Step.noSession => EmptyView(
            title: 'No session selected',
            message:
                'Start or resume a session to capture sheets for it.',
            icon: Icons.play_circle_outline,
            action: FilledButton.icon(
              onPressed: () => context.go(RoutePaths.sessions),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Go to sessions'),
            ),
          ),
          _Step.error => FailureView(
            failure: _loadFailure ?? const UnexpectedFailure(),
            onRetry: _load,
          ),
          _Step.identify => _IdentifyStep(
            roster: _roster,
            selectedStudentId: _selectedStudentId,
            omrIdController: _omrIdController,
            isBusy: _isBusy,
            failure: _loadFailure,
            onStudentChanged: (String? id) =>
                setState(() => _selectedStudentId = id),
            onCapture: () => _capture(
              () => ref.read(imagePickerServiceProvider).captureFromCamera(),
            ),
            onPickFromGallery: () => _capture(
              () => ref.read(imagePickerServiceProvider).pickFromGallery(),
            ),
          ),
          _Step.reviewing => _ReviewStep(
            report: _qualityReport,
            failure: _loadFailure,
            canOverride: authorization.can(Permission.overrideQualityGate),
            onRetake: _retake,
            onSave: _saveSubmission,
            onUseAnyway: _useAnyway,
          ),
        },
      ),
      floatingActionButton: _step == _Step.identify
          ? FloatingActionButton.extended(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
            )
          : null,
    );
  }
}

final class _IdentifyStep extends StatelessWidget {
  const _IdentifyStep({
    required this.roster,
    required this.selectedStudentId,
    required this.omrIdController,
    required this.isBusy,
    required this.failure,
    required this.onStudentChanged,
    required this.onCapture,
    required this.onPickFromGallery,
  });

  final List<Student> roster;
  final String? selectedStudentId;
  final TextEditingController omrIdController;
  final bool isBusy;
  final Failure? failure;
  final ValueChanged<String?> onStudentChanged;
  final VoidCallback onCapture;
  final VoidCallback onPickFromGallery;

  bool get _canCapture =>
      selectedStudentId != null && omrIdController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: <Widget>[
      if (failure != null) ...<Widget>[
        InfoBanner(
          message: failure!.userMessage,
          icon: Icons.error_outline,
          isWarning: true,
        ),
        const SizedBox(height: 16),
      ],
      Text('Whose sheet is this?', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: selectedStudentId,
        decoration: const InputDecoration(labelText: 'Student'),
        items: <DropdownMenuItem<String>>[
          for (final Student student in roster)
            DropdownMenuItem<String>(
              value: student.studentId,
              child: Text(student.studentName),
            ),
        ],
        onChanged: onStudentChanged,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: omrIdController,
        decoration: const InputDecoration(
          labelText: 'Printed OMR ID',
          helperText: 'Type the number printed on the sheet',
        ),
        keyboardType: TextInputType.number,
        onChanged: (_) {
          // Rebuilds via the StatefulWidget parent, which owns this
          // controller — see the enabling check in the buttons below.
        },
      ),
      const SizedBox(height: 24),
      ListenableBuilder(
        listenable: omrIdController,
        builder: (BuildContext context, Widget? _) => Column(
          children: <Widget>[
            FilledButton.icon(
              onPressed: isBusy || !_canCapture ? null : onCapture,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Capture from camera'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isBusy || !_canCapture ? null : onPickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from gallery'),
            ),
          ],
        ),
      ),
      if (isBusy) ...<Widget>[
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
      ],
    ],
  );
}

final class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.report,
    required this.failure,
    required this.canOverride,
    required this.onRetake,
    required this.onSave,
    required this.onUseAnyway,
  });

  final ImageQualityReport? report;
  final Failure? failure;
  final bool canOverride;
  final VoidCallback onRetake;
  final VoidCallback onSave;
  final VoidCallback onUseAnyway;

  @override
  Widget build(BuildContext context) {
    if (failure != null) {
      return FailureView(failure: failure!, onRetry: onRetake, retryLabel: 'Retake');
    }
    final ImageQualityReport quality = report!;
    final bool passed = quality.verdict == ImageQualityVerdict.pass;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Icon(
          passed ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 56,
          color: passed ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          passed ? 'Quality check passed' : 'Quality check failed',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (!passed) ...<Widget>[
          const SizedBox(height: 12),
          for (final String reason in quality.failureReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $reason', textAlign: TextAlign.center),
            ),
        ],
        const SizedBox(height: 24),
        if (passed)
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          )
        else ...<Widget>[
          OutlinedButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.replay_outlined),
            label: const Text('Retake'),
          ),
          if (canOverride) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onUseAnyway,
              icon: const Icon(Icons.warning_amber_outlined),
              label: const Text('Use Anyway'),
            ),
          ],
        ],
      ],
    );
  }
}
