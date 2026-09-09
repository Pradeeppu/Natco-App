/// OMR capture: the camera framing screen and the quality gate that follows.
///
/// Design preview ahead of Phase 5. The viewfinder here is a mock — no camera
/// is opened — but the framing guides, the check list and the three-way
/// outcome are the real interaction being reviewed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/widgets/preview_kit.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

/// One line of the quality gate.
final class _Check {
  const _Check(this.label, this.passed, {this.detail});
  final String label;
  final bool passed;
  final String? detail;
}

final class OmrCaptureScreen extends ConsumerStatefulWidget {
  const OmrCaptureScreen({super.key});

  @override
  ConsumerState<OmrCaptureScreen> createState() => _OmrCaptureScreenState();
}

class _OmrCaptureScreenState extends ConsumerState<OmrCaptureScreen> {
  /// `null` before a capture, then the gate result being previewed.
  bool? _passed;

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final bool canOverride = session.authorization.can(
      Permission.overrideQualityGate,
    );

    return PreviewScaffold(
      title: 'Capture OMR',
      phase: 'Phase 5',
      children: <Widget>[
        if (_passed == null) ..._viewfinder() else ..._gate(canOverride),
      ],
    );
  }

  List<Widget> _viewfinder() {
    final ThemeData theme = Theme.of(context);
    return <Widget>[
      const _ViewfinderMock(),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Align the sheet inside the frame',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              ...<String>[
                'Keep all four corner markers visible',
                'Avoid shadows falling across the sheet',
                'Hold the phone steady and parallel to the page',
              ].map(
                (String tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.check,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tip, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => setState(() => _passed = true),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Capture'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => setState(() => _passed = false),
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Choose from gallery'),
      ),
      const SizedBox(height: 12),
      Text(
        'Both buttons show a sample gate result — Capture previews a pass, '
        'gallery previews a failure.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _gate(bool canOverride) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final bool passed = _passed ?? false;

    final List<_Check> checks = passed
        ? const <_Check>[
            _Check('Sheet detected', true),
            _Check('Four registration markers found', true),
            _Check('Orientation correct', true),
            _Check('Focus', true, detail: 'Sharp'),
            _Check('Lighting', true, detail: 'Even'),
            _Check('OMR ID read', true, detail: '0001827'),
          ]
        : const <_Check>[
            _Check('Sheet detected', true),
            _Check('Four registration markers found', false,
                detail: 'Only 3 found — bottom-left corner is cut off'),
            _Check('Orientation correct', true),
            _Check('Focus', true, detail: 'Sharp'),
            _Check('Lighting', false, detail: 'Too dark on the right edge'),
            _Check('OMR ID read', false, detail: 'Not legible'),
          ];

    return <Widget>[
      Card(
        color: passed ? status.successContainer : status.dangerContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(
                passed ? Icons.check_circle_outline : Icons.error_outline,
                color: passed ? status.success : status.danger,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      passed ? 'Ready to process' : 'Scan failed',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: passed ? status.success : status.danger,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      passed
                          ? 'The sheet is readable. Processing runs on this '
                                'device.'
                          : 'Two checks did not pass. Please retake the '
                                'photograph.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: passed ? status.success : status.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      PreviewSection(
        title: 'Image quality',
        child: PreviewListCard(
          children: previewDivided(
            checks
                .map(
                  (_Check c) => ListTile(
                    leading: Icon(
                      c.passed ? Icons.check_circle : Icons.cancel,
                      color: c.passed ? status.success : status.danger,
                      size: 20,
                    ),
                    title: Text(c.label),
                    subtitle: c.detail == null ? null : Text(c.detail!),
                    dense: true,
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
      if (passed)
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Process sheet'),
        )
      else ...<Widget>[
        FilledButton.icon(
          onPressed: () => setState(() => _passed = null),
          icon: const Icon(Icons.refresh),
          label: const Text('Retake'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: canOverride ? () {} : null,
          child: const Text('Use anyway'),
        ),
        const SizedBox(height: 8),
        Text(
          canOverride
              ? 'Your role may waive the gate. The waiver is recorded against '
                    'you with a reason.'
              : 'Only a Supervisor may waive the quality gate. Retake the '
                    'photograph instead.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => setState(() => _passed = null),
        child: const Text('Cancel'),
      ),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Phase 5 writes the original image to the device before any of '
            'this runs, so killing the app mid-capture loses nothing. The '
            'original is kept as evidence and can never be replaced or '
            'deleted by a client.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    ];
  }
}

/// A drawn stand-in for the camera preview: an OMR sheet inside framing
/// guides, with the four registration markers the pipeline looks for.
final class _ViewfinderMock extends StatelessWidget {
  const _ViewfinderMock();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.78,
                heightFactor: 0.84,
                child: CustomPaint(painter: _SheetPainter(theme)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                  ),
                  child: Text(
                    'Sheet detected · 4 markers',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(this.theme);

  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint sheet = Paint()..color = theme.colorScheme.onInverseSurface;
    final RRect body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(body, sheet);

    // Four registration markers, one per corner.
    final Paint marker = Paint()..color = theme.colorScheme.inverseSurface;
    const double m = 12;
    const double inset = 10;
    for (final Offset corner in <Offset>[
      const Offset(inset, inset),
      Offset(size.width - inset - m, inset),
      Offset(inset, size.height - inset - m),
      Offset(size.width - inset - m, size.height - inset - m),
    ]) {
      canvas.drawRect(corner & const Size(m, m), marker);
    }

    // Suggestion of bubble rows, so the frame reads as an OMR sheet.
    final Paint bubble = Paint()
      ..color = theme.colorScheme.inverseSurface.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final double top = size.height * 0.26;
    final double rowGap = (size.height * 0.62) / 11;
    for (int row = 0; row < 11; row++) {
      for (int col = 0; col < 4; col++) {
        canvas.drawCircle(
          Offset(size.width * (0.30 + col * 0.16), top + row * rowGap),
          4.2,
          bubble,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SheetPainter oldDelegate) => false;
}
