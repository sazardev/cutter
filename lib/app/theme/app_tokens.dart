import 'package:flutter/widgets.dart';

/// Spacing scale on the 4dp grid (DESIGN.md: 0, 4, 8, 12, 16, 24, 32, 40,
/// 48, 64).
abstract final class AppSpacing {
  const AppSpacing._();

  /// No spacing (0dp).
  static const double none = 0;

  /// Extra small spacing (4dp).
  static const double xs = 4;

  /// Small spacing (8dp).
  static const double sm = 8;

  /// Medium spacing (12dp).
  static const double md = 12;

  /// Large spacing (16dp).
  static const double lg = 16;

  /// Extra large spacing (24dp).
  static const double xl = 24;

  /// Double extra large spacing (32dp).
  static const double xxl = 32;

  /// Huge spacing (40dp).
  static const double huge = 40;

  /// Giant spacing (48dp).
  static const double giant = 48;

  /// Maximum spacing (64dp).
  static const double max = 64;
}

/// Shape scale radii (DESIGN.md: extra-small to extra-large).
abstract final class AppRadii {
  const AppRadii._();

  /// Extra small radius (4dp): menus, snackbars.
  static const double extraSmall = 4;

  /// Small radius (8dp): chips.
  static const double small = 8;

  /// Medium radius (12dp): cards.
  static const double medium = 12;

  /// Large radius (16dp): FABs, sheets.
  static const double large = 16;

  /// Extra large radius (28dp): dialogs, bottom sheets.
  static const double extraLarge = 28;
}

/// Fixed component sizes used by the editor.
abstract final class AppSizes {
  const AppSizes._();

  /// Minimum touch target (48dp).
  static const double minTarget = 48;

  /// Height of one timeline layer row.
  static const double timelineRowHeight = 56;

  /// Width of the layer header column in the timeline.
  static const double layerHeaderWidth = 96;

  /// Width of a clip trim handle.
  static const double trimHandleWidth = 16;
}

/// Window size classes from DESIGN.md.
enum WindowClass {
  /// Narrow phone windows (under 600dp).
  compact,

  /// Large phones and small tablets (600 to 839dp).
  medium,

  /// Tablets and wider windows (840dp and up).
  expanded,
}

const double _mediumBreakpoint = 600;
const double _expandedBreakpoint = 840;
const double _compactMargin = 16;
const double _wideMargin = 24;

/// Maps a window width in dp to its size class.
WindowClass windowClassOf(double width) {
  if (width < _mediumBreakpoint) return WindowClass.compact;
  if (width < _expandedBreakpoint) return WindowClass.medium;
  return WindowClass.expanded;
}

/// Page margin for a window class: 16dp compact, 24dp medium and up.
double marginFor(WindowClass windowClass) {
  switch (windowClass) {
    case WindowClass.compact:
      return _compactMargin;
    case WindowClass.medium:
    case WindowClass.expanded:
      return _wideMargin;
  }
}

/// Returns [normal], or zero when the user disabled animations (reduced
/// motion).
Duration motionDuration(BuildContext context, Duration normal) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
}
