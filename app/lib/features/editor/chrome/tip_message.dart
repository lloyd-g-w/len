import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/preferences.dart';

/// One-time hints about input that has no visible affordance, in order of
/// priority when several are due at once.
enum EditorTip {
  /// The stylus side button (on a stylus contact, from the second opening
  /// of a notebook with the pen on: the first has the "Stylus detected"
  /// message).
  penButton,

  /// Hold to snap (after a line or shape drawn by hand).
  holdToSnap,

  /// What the lasso does (when it is picked; it has no options).
  lasso,

  /// Scribble to erase (when the eraser is picked again).
  scribble,
}

/// What a shown tip says.
@immutable
class TipMessage {
  const TipMessage(this.tip, this.icon, this.text);

  final EditorTip tip;
  final IconData icon;
  final String text;
}

/// [tip] phrased for the side button's action ([penButton]) and the
/// notebook ([pdf]: it has PDF pages); null if it doesn't apply.
TipMessage? tipMessage(EditorTip tip, {required PenButtonAction penButton, bool pdf = false}) =>
    switch (tip) {
      EditorTip.penButton => switch (penButton) {
        PenButtonAction.eraser => TipMessage(
          tip,
          Symbols.draw_sharp,
          'Hold the pen’s side button to erase',
        ),
        PenButtonAction.lasso => TipMessage(
          tip,
          Symbols.highlight_alt_sharp,
          'Hold the pen’s side button to select with the lasso',
        ),
        PenButtonAction.none => null,
      },
      EditorTip.holdToSnap => TipMessage(
        tip,
        Symbols.shape_line_sharp,
        'Hold the pen still at the end of a line or shape to snap it clean',
      ),
      EditorTip.lasso => TipMessage(
        tip,
        Symbols.highlight_alt_sharp,
        pdf
            ? 'Circle ink, text or images to select them; tap PDF text to select it'
            : 'Circle ink, text or images to select them',
      ),
      EditorTip.scribble => TipMessage(
        tip,
        Symbols.ink_eraser_sharp,
        'Or scribble over ink with the pen to erase it',
      ),
    };
