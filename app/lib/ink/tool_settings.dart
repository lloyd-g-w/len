import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../domain/stroke.dart';
import '../domain/text/text_data.dart';
import 'editor_tool.dart';
import 'pen/eraser_config.dart';
import 'pen/pen_config.dart';
import 'pen/pen_defaults.dart';
import 'pen/recent_colors.dart';
import 'selection/lasso_config.dart';
import 'shapes/shape_fill.dart';
import 'tools/laser_config.dart';

export '../domain/shape_kind.dart';
export 'editor_tool.dart';
export 'pen/eraser_config.dart';
export 'pen/pen_config.dart';
export 'pen/pen_defaults.dart';
export 'selection/lasso_config.dart';
export 'shapes/shape_fill.dart';
export 'tools/laser_config.dart';

part 'tool_settings_state.dart';

/// Current tool selection, per-pen customisation and input preferences.
///
/// With a [store], customisation is restored on creation and saved
/// (debounced) whenever it changes.
class ToolSettings extends _ToolState {
  ToolSettings({
    bool? stylusOnly,
    bool penButtonErases = false,
    bool holdToStraighten = true,
    bool scribbleToErase = true,
    SettingsRepository? store,
  }) : super(stylusOnly, penButtonErases, holdToStraighten, scribbleToErase, store);

  /// The inks offered in the toolbar: the pen (ballpoint) and highlighter.
  static const List<InkTool> inks = [InkTool.ballpoint, InkTool.highlighter];

  /// The version of the saved settings' format: 2 since the pen's default
  /// stabiliser became 30 % (a pen saved before at the old default, off,
  /// is upgraded on restore).
  static const int prefsVersion = 2;

  /// The tool in hand. Picking another one starts writing ([reading] off).
  EditorTool get tool => _tool;
  set tool(EditorTool value) {
    if (value == _tool) return;
    _select(value);
    notifyListeners();
  }

  void _select(EditorTool value) {
    _reading = false;
    _tool = value;
    if (_used.first != value) _used = [value, ..._used.where((t) => t != value).take(3)];
  }

  /// The tool used before [tool], for the phone's one-tap toggle (pen ↔
  /// eraser, pen ↔ highlighter). At first the eraser. A stylus writer whose
  /// side button erases ([stylusOnly] and [penButtonErases]) has the eraser
  /// on the pen already: the eraser is skipped, and the toggle starts at
  /// the highlighter (the pen, from the highlighter).
  EditorTool get previousTool {
    final skipEraser = (_stylusOnly ?? false) && _penButtonErases;
    for (final t in _used.skip(1)) {
      if (!(skipEraser && t == EditorTool.eraser)) return t;
    }
    if (!skipEraser) return EditorTool.eraser;
    return _tool == EditorTool.highlighter ? EditorTool.pen : EditorTool.highlighter;
  }

  /// Picks [value] from the toolbar: the active tool too starts writing.
  void pick(EditorTool value) {
    if (value == _tool && !_reading) return;
    _select(value);
    notifyListeners();
  }

  /// Swaps [tool] and [previousTool].
  void togglePrevious() => tool = previousTool;

  /// Whether the stylus side button erases (`PenButtonAction.eraser`); see
  /// [previousTool].
  bool get penButtonErases => _penButtonErases;
  set penButtonErases(bool value) {
    if (value == _penButtonErases) return;
    _penButtonErases = value;
    notifyListeners();
  }

  /// The ink the colour/width controls currently edit: the highlighter
  /// while it is the tool, else the pen.
  InkTool get activeInk =>
      _tool == EditorTool.highlighter ? InkTool.highlighter : InkTool.ballpoint;

  /// The customisation of [tool].
  PenConfig configOf(InkTool tool) => _configs[tool]!;

  /// The customisation of [activeInk].
  PenConfig get activeConfig => configOf(activeInk);

  /// Replaces the configuration of [tool].
  void updateConfig(InkTool tool, PenConfig Function(PenConfig) update) {
    _configs[tool] = update(configOf(tool));
    _changed();
  }

  /// The style a new stroke with [tool] gets.
  StrokeStyle styleFor(InkTool tool) => configOf(tool).styleFor(tool);

  /// Selects colour slot [index] of the active ink (switching to the pen
  /// from tools that draw no ink), or of the laser while it is the tool.
  void selectColor(int index) {
    if (_tool == EditorTool.laser) {
      if (index >= 0 && index < _laser.colors.length) laser = _laser.copyWith(colorIndex: index);
      return;
    }
    if (index < 0 || index >= activeConfig.colors.length) return;
    _leaveNonInk();
    updateConfig(activeInk, (c) => c.copyWith(colorIndex: index));
  }

  /// Selects width slot [index] of the active ink (switching to the pen
  /// from tools that draw no ink), or size slot [index] of the laser while
  /// it is the tool.
  void selectWidth(int index) {
    if (_tool == EditorTool.laser) {
      if (index >= 0 && index < _laser.sizes.length) laser = _laser.copyWith(sizeIndex: index);
      return;
    }
    if (index < 0 || index >= activeConfig.widths.length) return;
    _leaveNonInk();
    updateConfig(activeInk, (c) => c.copyWith(widthIndex: index));
  }

  /// Steps the active ink's width selection (the laser's size, while it
  /// is the tool) by [delta] slots, clamped.
  void stepWidth(int delta) {
    if (_tool == EditorTool.laser) {
      selectWidth((_laser.sizeIndex + delta).clamp(0, _laser.sizes.length - 1));
      return;
    }
    final c = activeConfig;
    selectWidth((c.widthIndex + delta).clamp(0, c.widths.length - 1));
  }

  void _leaveNonInk() {
    if (!_tool.usesInk) _select(EditorTool.pen);
  }

  /// The Shape tool's shape and fill until changed (and after Reset).
  static const defaultShape = ShapeKind.rectangle;
  static const defaultShapeFill = ShapeFill.none;

  /// The shape the Shape tool draws.
  ShapeKind get shape => _shape;
  set shape(ShapeKind value) {
    _shape = value;
    _select(EditorTool.shape);
    _changed();
  }

  /// How the Shape tool fills the closed shapes it draws.
  ShapeFill get shapeFill => _shapeFill;
  set shapeFill(ShapeFill value) {
    if (value == _shapeFill) return;
    _shapeFill = value;
    _changed();
  }

  /// How the laser pointer looks.
  LaserConfig get laser => _laser;
  set laser(LaserConfig value) {
    if (value == _laser) return;
    _laser = value;
    _changed();
  }

  /// What and how the lasso selects.
  LassoConfig get lasso => _lasso;
  set lasso(LassoConfig value) {
    if (value == _lasso) return;
    _lasso = value;
    _changed();
  }

  /// Formatting of new text boxes (its text is ignored).
  TextData get textStyle => _text;
  set textStyle(TextData value) {
    _text = value.copyWith(text: '');
    _changed();
  }

  EraserConfig get eraser => _eraser;
  set eraser(EraserConfig value) {
    _eraser = value;
    _changed();
  }

  /// Eraser radius in screen pixels (independent of zoom).
  double get eraserRadius => _eraser.radius;

  /// Holding the pen still at the end of a stroke straightens it. A
  /// writing gesture of the app's preferences (Settings → Writing), which
  /// the editor mirrors here; not saved with the tools.
  bool get holdToStraighten => _holdToStraighten;
  set holdToStraighten(bool value) {
    if (value == _holdToStraighten) return;
    _holdToStraighten = value;
    notifyListeners();
  }

  /// A quick back-and-forth scribble with the pen over ink erases it. Like
  /// [holdToStraighten], mirrored from the preferences.
  bool get scribbleToErase => _scribbleToErase;
  set scribbleToErase(bool value) {
    if (value == _scribbleToErase) return;
    _scribbleToErase = value;
    notifyListeners();
  }

  /// While the stabiliser holds the ink back from the pen, a hairline from
  /// the ink's tip to the pen shows where the ink is being pulled
  /// (`LiveInk.string`). Like [holdToStraighten], mirrored from the
  /// preferences.
  bool get showStabiliserString => _showStabiliserString;
  set showStabiliserString(bool value) {
    if (value == _showStabiliserString) return;
    _showStabiliserString = value;
    notifyListeners();
  }

  bool _showStabiliserString = true;

  /// Colours recently picked for quick colour slots (opaque ARGB), most
  /// recent first, at most [RecentColors.max].
  List<int> get recentColors => _recent;

  /// Notes [argb] as the most recently picked ink colour.
  void addRecentColor(int argb) {
    final recent = RecentColors.add(_recent, argb);
    if (identical(recent, _recent)) return;
    _recent = recent;
    _changed();
  }

  /// Palm rejection: only the stylus draws; fingers navigate. `null` means
  /// undecided — it turns on automatically when a stylus is first used.
  bool? get stylusOnly => _stylusOnly;
  set stylusOnly(bool? value) {
    if (value == _stylusOnly) return;
    _stylusOnly = value;
    if (value != null) _reading = false;
    notifyListeners();
  }

  /// Reading (R20-6): while fingers draw because no stylus was ever seen
  /// ([stylusOnly] null), one finger scrolls, zooms, taps links and opens
  /// the menu, as with palm rejection, until a tool is chosen (any change
  /// of [tool] or of its options, [pick], or `reading = false`). Never
  /// on once [stylusOnly] is decided: setting it then does nothing.
  bool get reading => _reading;
  set reading(bool value) {
    if (value && _stylusOnly != null) return;
    if (value == _reading) return;
    _reading = value;
    notifyListeners();
  }

  /// Whether one finger pans and zooms rather than draws: palm rejection
  /// ([stylusOnly]) or [reading].
  bool get fingersNavigate => (_stylusOnly ?? false) || _reading;

  /// Takes over [other]'s tool and customisation (linked tools of a split
  /// view). Notifies only when something differed; [other] persists it.
  void adopt(ToolSettings other) {
    final tool = other._tool;
    final same =
        tool == _tool &&
        identical(_used, other._used) &&
        _eraser == other._eraser &&
        _shape == other._shape &&
        _shapeFill == other._shapeFill &&
        _laser == other._laser &&
        _lasso == other._lasso &&
        identical(_text, other._text) &&
        identical(_recent, other._recent) &&
        inks.every((t) => identical(_configs[t], other._configs[t]));
    if (same) return;
    _tool = tool;
    _used = other._used;
    _configs.addAll(other._configs);
    _eraser = other._eraser;
    _shape = other._shape;
    _shapeFill = other._shapeFill;
    _laser = other._laser;
    _lasso = other._lasso;
    _text = other._text;
    _recent = other._recent;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_saveTimer != null) _save();
    super.dispose();
  }
}
