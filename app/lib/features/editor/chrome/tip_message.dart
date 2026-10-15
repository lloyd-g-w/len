import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/preferences.dart';
import '../../../ink/selection/lasso_config.dart';

/// One-time hints about input that has no visible affordance, in order of
/// priority when several are due at once.
enum EditorTip {
  /// One finger writes, two scroll (on a finger's first stroke while
  /// fingers draw until a stylus is seen: a phone without one).
  fingers,

  /// The stylus side button (on a stylus contact, from the second opening
  /// of a notebook with the pen on: the first has the "Stylus detected"
  /// message).
  penButton,

  /// Hold to snap (after a line or shape drawn by hand).
  holdToSnap,

  /// What the lasso does (when it is picked), in its shape's words.
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

/// [tip] phrased for the side button's action ([penButton]), the lasso's
/// [lasso] shape (a loop is circled, a rectangle dragged) and the notebook
/// ([pdf]: it has PDF pages); null if it doesn't apply.
TipMessage? tipMessage(
  EditorTip tip, {
  required PenButtonAction penButton,
  LassoShape lasso = LassoShape.freehand,
  bool pdf = false,
}) => switch (tip) {
  EditorTip.fingers => TipMessage(tip, Symbols.pinch_sharp, 'Two fingers scroll and zoom'),
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
    _lassoTip(lasso) + (pdf ? '; tap PDF text to select it' : ''),
  ),
  EditorTip.scribble => TipMessage(
    tip,
    Symbols.ink_eraser_sharp,
    'Or scribble over ink with the pen to erase it',
  ),
};

/// What the lasso tip asks for: a loop is circled, a rectangle dragged.
String _lassoTip(LassoShape shape) => switch (shape) {
  LassoShape.freehand => 'Circle ink, text or images to select them',
  LassoShape.rectangle => 'Drag a box around ink, text or images to select them',
};
