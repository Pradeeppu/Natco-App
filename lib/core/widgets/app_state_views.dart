/// Shared loading, error and empty states.
///
/// These exist so that no screen invents its own. Requirement section 41 asks
/// that every network operation has a loading indicator, a timeout, a retry
/// and an offline fallback, and section 40 that failures show a plain message
/// with a recovery action. Both are easier to honour when the widget that
/// honours them already exists.
library;

import 'package:flutter/material.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/errors/failure.dart';

/// A determinate-where-possible loading state with a label.
///
/// A bare spinner with no text is indistinguishable from a hung screen, which
/// is the failure mode requirement section 41 calls out.
final class LoadingView extends StatelessWidget {
  const LoadingView({this.message, this.progress, super.key});

  final String? message;

  /// 0.0-1.0 when known. `null` renders an indeterminate indicator.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(value: progress, strokeWidth: 3),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 20),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An error state built from a [Failure].
///
/// It renders [Failure.userMessage] and nothing else from the failure — the
/// diagnostic never reaches the screen (requirement section 40).
final class FailureView extends StatelessWidget {
  const FailureView({
    required this.failure,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.secondaryAction,
    super.key,
  });

  final Failure failure;

  /// Recovery action. Omitted only when there genuinely is nothing to retry.
  final VoidCallback? onRetry;
  final String retryLabel;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isOffline =
        failure.code == FailureCode.offline ||
        failure.code == FailureCode.network;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              isOffline ? Icons.cloud_off_outlined : Icons.error_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              failure.userMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
            if (secondaryAction != null) ...<Widget>[
              const SizedBox(height: 12),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}

/// An empty state that says what to do next rather than only that there is
/// nothing here.
final class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// An inline banner for a non-blocking condition — working offline, a stale
/// cached session, a pending sync.
final class InfoBanner extends StatelessWidget {
  const InfoBanner({
    required this.message,
    this.icon = Icons.info_outline,
    this.action,
    this.isWarning = false,
    super.key,
  });

  final String message;
  final IconData icon;
  final Widget? action;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = isWarning
        ? theme.statusColors.warningContainer
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = isWarning
        ? theme.statusColors.warning
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: background,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
          if (action != null) ...<Widget>[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}
