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
/// * We use `google_mlkit_document_scanner` on Android/iOS to provide a
///   beautiful edge-detecting, perspective-correcting "Adobe Scan" style UI.
///   On platforms where this isn't supported (like Web or Windows), we fall
///   back to the standard `image_picker` camera.
/// * The OMR ID is typed by hand. Reading it off the sheet automatically is
///   phase 6's job (bubble-grid decoding); until that pipeline exists, the
///   person capturing is the only source for it.
///
/// The write order matters (Critical Rule 12): [OmrImageWriter] puts the
/// photo durably on disk *before* [OmrValidationRepository.createSubmission]
/// is ever called, so a crash between the two loses at most an unlinked
/// database row, never the evidence.
library;

import 'dart:async' show unawaited;
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/presentation/controller/session_controllers.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/omr_capture/domain/service/omr_drive_backup_service.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/image_quality_analyzer.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_image_writer.dart';
import 'package:natco_app/features/schools/domain/entity/school.dart';
import 'package:natco_app/features/schools/presentation/controller/hierarchy_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

Result<ImageQualityReport> _analyzeQualityIsolate(Uint8List bytes) =>
    ImageQualityAnalyzer.analyze(imageBytes: bytes);

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
            ? const _SessionPicker()
            : _SessionLoader(sessionId: sessionId),
      ),
    );
  }
}

final class _SessionPicker extends ConsumerStatefulWidget {
  const _SessionPicker();

  @override
  ConsumerState<_SessionPicker> createState() => _SessionPickerState();
}

class _SessionPickerState extends ConsumerState<_SessionPicker> {
  // Filters, not a wizard: with nothing picked every open session in scope
  // still shows below exactly as before, so a teacher with a single class
  // (the common case) never has to touch these to start capturing.
  String? _schoolFilter;
  String? _gradeFilter;
  String? _sectionFilter;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AssessmentSession>> asyncSessions = ref.watch(
      openSessionsProvider,
    );

    return asyncSessions.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Loading active sessions...'),
        ),
      ),
      error: (Object error, StackTrace _) => FailureView(
        failure: asFailure(error),
        onRetry: () => ref.invalidate(openSessionsProvider),
      ),
      data: (List<AssessmentSession> sessions) {
        if (sessions.isEmpty) {
          return EmptyView(
            title: 'No active assessment sessions',
            message:
                'Sheets must be linked to an active session so the right '
                'student roster and answer key are scored. Start a session '
                'from the Assessments tab.',
            icon: Icons.link_off_outlined,
            action: FilledButton.icon(
              onPressed: () => context.go(RoutePaths.assessments),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('View assessments'),
            ),
          );
        }

        final ThemeData theme = Theme.of(context);

        final List<String> schoolIds = <String>{
          for (final AssessmentSession s in sessions) s.schoolId,
        }.toList(growable: false)..sort();
        // Options never include a value already off the list (e.g. a
        // session closed elsewhere) — `DropdownButtonFormField` requires its
        // current value to be one of its items.
        final String? schoolFilter = schoolIds.contains(_schoolFilter)
            ? _schoolFilter
            : null;

        final List<AssessmentSession> bySchool = schoolFilter == null
            ? sessions
            : sessions
                  .where((AssessmentSession s) => s.schoolId == schoolFilter)
                  .toList(growable: false);

        final List<String> grades = <String>{
          for (final AssessmentSession s in bySchool) s.grade,
        }.toList(growable: false)..sort();
        final String? gradeFilter = grades.contains(_gradeFilter)
            ? _gradeFilter
            : null;

        final List<AssessmentSession> byGrade = gradeFilter == null
            ? bySchool
            : bySchool
                  .where((AssessmentSession s) => s.grade == gradeFilter)
                  .toList(growable: false);

        final List<String> sections = <String>{
          for (final AssessmentSession s in byGrade) s.section,
        }.toList(growable: false)..sort();
        final String? sectionFilter = sections.contains(_sectionFilter)
            ? _sectionFilter
            : null;

        final List<AssessmentSession> visible = sectionFilter == null
            ? byGrade
            : byGrade
                  .where((AssessmentSession s) => s.section == sectionFilter)
                  .toList(growable: false);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Select an active session',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Filter by school, grade and section to find the right class, '
              'or pick straight from the list below.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: schoolFilter,
              // Long school names would otherwise force the closed dropdown
              // wider than the screen instead of truncating with ellipsis —
              // `isExpanded` constrains it to the available width.
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'School'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  child: Text('All schools'),
                ),
                for (final String id in schoolIds)
                  DropdownMenuItem<String?>(
                    value: id,
                    child: _SchoolLabel(schoolId: id),
                  ),
              ],
              onChanged: (String? value) => setState(() {
                _schoolFilter = value;
                _gradeFilter = null;
                _sectionFilter = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: gradeFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Grade'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(child: Text('All grades')),
                for (final String grade in grades)
                  DropdownMenuItem<String?>(
                    value: grade,
                    child: Text('Grade $grade'),
                  ),
              ],
              onChanged: (String? value) => setState(() {
                _gradeFilter = value;
                _sectionFilter = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: sectionFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Section'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(child: Text('All sections')),
                for (final String section in sections)
                  DropdownMenuItem<String?>(
                    value: section,
                    child: Text('Section $section'),
                  ),
              ],
              onChanged: (String? value) =>
                  setState(() => _sectionFilter = value),
            ),
            const SizedBox(height: 20),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No open session matches that filter.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final AssessmentSession session in visible)
                _SessionCard(session: session),
          ],
        );
      },
    );
  }
}

/// A school's name, resolved from its id for the school filter dropdown —
/// `AssessmentSession` only carries `schoolId`, never a name.
final class _SchoolLabel extends ConsumerWidget {
  const _SchoolLabel({required this.schoolId});

  final String schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<School> school = ref.watch(schoolProvider(schoolId));
    return Text(
      school.whenOrNull(data: (School s) => s.schoolName) ?? schoolId,
      overflow: TextOverflow.ellipsis,
    );
  }
}

final class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final AssessmentSession session;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Grade ${session.grade} • Section ${session.section}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(
                  label: session.status.displayName,
                  tone: session.status.acceptsCapture
                      ? StatusTone.success
                      : StatusTone.pending,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Assessment: ${session.assessmentId}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  Icons.people_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${session.pendingCount} pending, '
                    '${session.capturedCount} captured',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Full-width, not tucked beside the counts: this app's
            // `filledButtonTheme` sets `minimumSize: Size.fromHeight(48)`,
            // which is an *infinite* minimum width — a filled button laid out
            // as a Row's non-flex child throws rather than shrinking.
            if (session.status.acceptsCapture)
              FilledButton.tonalIcon(
                onPressed: () => context.go(
                  '${RoutePaths.omrCapture}?sessionId=${session.sessionId}',
                ),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Start capture'),
              )
            else
              // A READY session cannot take a sheet until it is started, and
              // starting it is the session screen's decision to own, not a
              // side effect of opening the camera.
              OutlinedButton.icon(
                onPressed: () => context.push(
                  RoutePaths.of(
                    RoutePaths.assessmentSession,
                    <String, String>{'sessionId': session.sessionId},
                  ),
                ),
                icon: const Icon(Icons.play_arrow_outlined, size: 18),
                label: const Text('Open session'),
              ),
          ],
        ),
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
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(
              value: widget.session.totalStudents == 0
                  ? 0
                  : widget.session.capturedCount / widget.session.totalStudents,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Batch: ${widget.session.capturedCount} of '
            '${widget.session.totalStudents} captured',
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
            decoration: InputDecoration(
              labelText: 'OMR ID',
              helperText: 'Printed on the sheet — read it by hand for now. '
                  'School, grade, section and assessment are already set '
                  'for this whole batch (Grade ${widget.session.grade} • '
                  'Section ${widget.session.section} • '
                  '${widget.session.assessmentId}) — you only pick the '
                  'student and the sheet.',
              helperMaxLines: 3,
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
    if (source == ImageSource.camera && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final DocumentScanner scanner = DocumentScanner(
          options: DocumentScannerOptions(
            documentFormats: const {DocumentFormat.jpeg},
            mode: ScannerMode.full,
            pageLimit: 1,
            isGalleryImport: true,
          ),
        );

        final DocumentScanningResult scannerResult = await scanner.scanDocument();
        if (scannerResult.images == null || scannerResult.images!.isEmpty || !mounted) {
          return;
        }

        final Uint8List bytes = await File(scannerResult.images!.first).readAsBytes();
        setState(() => _busy = true);
        final Result<ImageQualityReport> qualityResult = await compute(
          _analyzeQualityIsolate,
          bytes,
        );
        if (!mounted) {
          return;
        }
        setState(() => _busy = false);
        qualityResult.fold(
          onSuccess: (ImageQualityReport report) => setState(() {
            _imageBytes = bytes;
            _quality = report;
            _overrideReason = null;
          }),
          onFailure: (Failure failure) => _showMessage(failure.userMessage),
        );
        return;
      } catch (e) {
        // Fall back to ImagePicker if scanner fails
        if (mounted) {
          setState(() => _busy = false);
        }
      }
    }

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
    setState(() => _busy = true);
    final Result<ImageQualityReport> result = await compute(
      _analyzeQualityIsolate,
      bytes,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
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

      // Back up to Drive (fire-and-forget so it doesn't block capture flow).
      // No Google sign-in on device: this calls a Cloud Function that holds
      // the shared credential server-side — see
      // docs/13-google-drive-backup-setup.md.
      final OmrDriveBackupService driveBackupService = ref.read(
        omrDriveBackupServiceProvider,
      );
      final String fileName = '${omrId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String folderName = 'OMR_Captures_${widget.session.assessmentId}';

      unawaited(
        driveBackupService
            .backup(
              file: File(written.valueOrNull!),
              folderName: folderName,
              fileName: fileName,
            )
            .then((bool success) {
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Image backed up to Google Drive ($folderName)')),
            );
          }
        }),
      );

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

      // Trigger background OMR processing so the sheet is decoded into answers and advances status
      unawaited(
        ref
            .read(omrValidationRepositoryProvider)
            .processSubmission(
              omrId,
              template: OmrTemplate.natcoV1(),
              questionCount: assessment.totalQuestions,
            ),
      );

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
