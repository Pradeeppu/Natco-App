/// Material 3 theme.
///
/// The design direction (requirement section 62) is a modern education /
/// operations dashboard: status first, next action second, exceptions
/// prominent. That translates into a small set of decisions here:
///
/// * **Semantic status colours are part of the theme, not ad-hoc.** Pending,
///   success, warning and danger appear on almost every screen (sync state,
///   validation state, quality verdicts), so they are defined once and read
///   through [NatcoStatusColors] rather than picked per widget.
/// * **Large touch targets and readable type by default.** Field users are
///   often standing, one-handed, on a 5-inch screen in daylight. Minimum
///   interactive height is 48dp and body text does not go below 14sp.
/// * **Contrast over decoration.** Colours are chosen so that text on them
///   clears WCAG AA at body size; nothing important is conveyed by hue alone —
///   status is always colour *and* icon *and* text (requirement section 56).
library;

import 'package:flutter/material.dart';

/// Brand seed. A deep teal reads as institutional and calm rather than
/// childish, and stays legible in bright outdoor light.
const Color kNatcoSeed = Color(0xFF12595B);

/// Semantic colours that Material's scheme does not provide.
///
/// Registered as a [ThemeExtension] so widgets read them from the theme
/// instead of importing constants, which is what makes the dark variant work
/// without a single `if (isDark)` in a widget.
@immutable
final class NatcoStatusColors extends ThemeExtension<NatcoStatusColors> {
  const NatcoStatusColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.pending,
    required this.onPending,
    required this.pendingContainer,
  });

  /// Confirmed, synced, correct.
  final Color success;
  final Color onSuccess;
  final Color successContainer;

  /// Needs attention but not broken: medium confidence, retry scheduled.
  final Color warning;
  final Color onWarning;
  final Color warningContainer;

  /// Failed, invalid, duplicate, unreadable.
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;

  /// Neutral in-progress: queued, uploading, processing.
  final Color pending;
  final Color onPending;
  final Color pendingContainer;

  static const NatcoStatusColors light = NatcoStatusColors(
    success: Color(0xFF14713D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCF3E4),
    warning: Color(0xFF8A5300),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFEBCC),
    danger: Color(0xFFB3261E),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFCE8E6),
    pending: Color(0xFF44546A),
    onPending: Color(0xFFFFFFFF),
    pendingContainer: Color(0xFFE6EAF0),
  );

  static const NatcoStatusColors dark = NatcoStatusColors(
    success: Color(0xFF6FD79B),
    onSuccess: Color(0xFF00351A),
    successContainer: Color(0xFF1B4B30),
    warning: Color(0xFFFFC46B),
    onWarning: Color(0xFF422C00),
    warningContainer: Color(0xFF5C4200),
    danger: Color(0xFFFFB4AB),
    onDanger: Color(0xFF690005),
    dangerContainer: Color(0xFF7A2721),
    pending: Color(0xFFB6C2D4),
    onPending: Color(0xFF1F2733),
    pendingContainer: Color(0xFF333C4A),
  );

  @override
  NatcoStatusColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? pending,
    Color? onPending,
    Color? pendingContainer,
  }) => NatcoStatusColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    danger: danger ?? this.danger,
    onDanger: onDanger ?? this.onDanger,
    dangerContainer: dangerContainer ?? this.dangerContainer,
    pending: pending ?? this.pending,
    onPending: onPending ?? this.onPending,
    pendingContainer: pendingContainer ?? this.pendingContainer,
  );

  @override
  NatcoStatusColors lerp(NatcoStatusColors? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return NatcoStatusColors(
      success: mix(success, other.success),
      onSuccess: mix(onSuccess, other.onSuccess),
      successContainer: mix(successContainer, other.successContainer),
      warning: mix(warning, other.warning),
      onWarning: mix(onWarning, other.onWarning),
      warningContainer: mix(warningContainer, other.warningContainer),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      dangerContainer: mix(dangerContainer, other.dangerContainer),
      pending: mix(pending, other.pending),
      onPending: mix(onPending, other.onPending),
      pendingContainer: mix(pendingContainer, other.pendingContainer),
    );
  }
}

/// Convenient access to the status palette.
extension NatcoThemeAccess on ThemeData {
  NatcoStatusColors get statusColors =>
      extension<NatcoStatusColors>() ?? NatcoStatusColors.light;
}

abstract final class NatcoTheme {
  /// Minimum height for anything tappable. Above Material's 48dp default in
  /// the places that matter most, because the primary actions here are pressed
  /// while holding a stack of OMR sheets.
  static const double minTouchTarget = 48;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: kNatcoSeed,
      brightness: brightness,
    );
    final bool isDark = brightness == Brightness.dark;
    final NatcoStatusColors status = isDark
        ? NatcoStatusColors.dark
        : NatcoStatusColors.light;

    final ThemeData base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      extensions: <ThemeExtension<Object?>>[status],
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      textTheme: _textTheme(base.textTheme),
      // Primary actions get strong emphasis; secondary actions are outlined
      // (requirement section 62).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(minTouchTarget),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(minTouchTarget),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        // A visible border rather than an underline: in daylight on a cheap
        // screen, an underline-only field is easy to miss entirely.
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        color: scheme.surface,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        // Labels always shown: an icon-only bar forces the user to learn
        // glyphs, and requirement section 56 asks for icons with text.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    // Nothing below 14sp for body copy.
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14.5, height: 1.4),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}
