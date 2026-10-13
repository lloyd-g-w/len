import 'package:flutter/widgets.dart';

/// The named colours of the design language (DESIGN §1) for one
/// brightness. Features use the `ColorScheme` roles they map to (and
/// `Surfaces`); these names are for the theme and the shared components.
class Tones {
  const Tones._({
    required this.ink,
    required this.graphite,
    required this.pencil,
    required this.rule,
    required this.sheet,
    required this.board,
    required this.desk,
    required this.accent,
    required this.onAccent,
    required this.error,
  });

  /// Text, icons, primary buttons (`onSurface`).
  final Color ink;

  /// Secondary text, captions, idle icons (`onSurfaceVariant`).
  final Color graphite;

  /// Control outlines that must read, field rules (`outline`).
  final Color pencil;

  /// Hairlines and dividers (`outlineVariant`).
  final Color rule;

  /// Slips over the page: popovers, menus, dialogs, sheets, the palette.
  final Color sheet;

  /// The screen background and docked chrome (`surface`).
  final Color board;

  /// Around pages in the editor.
  final Color desk;

  /// Ruling blue, the one accent (`primary`): state, never decoration.
  final Color accent;

  /// Text and glyphs on [accent].
  final Color onAccent;

  /// Correction red: destructive commands and errors.
  final Color error;

  static const light = Tones._(
    ink: Color(0xFF000000),
    graphite: Color(0xFF5A5A5A),
    pencil: Color(0xFF8A8A8A),
    rule: Color(0xFFDCDCDC),
    sheet: Color(0xFFFFFFFF),
    board: Color(0xFFF4F4F4),
    desk: Color(0xFFE6E6E6),
    accent: Color(0xFF0068C9),
    onAccent: Color(0xFFFFFFFF),
    error: Color(0xFFC4161C),
  );

  static const dark = Tones._(
    ink: Color(0xFFEFEFEF),
    graphite: Color(0xFFA6A6A6),
    pencil: Color(0xFF7A7A7A),
    rule: Color(0xFF383838),
    sheet: Color(0xFF262626),
    board: Color(0xFF1A1A1A),
    desk: Color(0xFF000000),
    accent: Color(0xFF4DA3FF),
    onAccent: Color(0xFF000000),
    error: Color(0xFFFF6B6B),
  );

  /// The tones for [brightness].
  static Tones of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}
