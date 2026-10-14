import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../domain/stroke.dart';
import '../domain/text/text_data.dart';
import 'editor_tool.dart';
import 'pen/eraser_config.dart';
import 'pen/pen_config.dart';
import 'pen/recent_colors.dart';
import 'shapes/shape_fill.dart';
import 'shapes/shape_kind.dart';
import 'tools/laser_config.dart';

export 'editor_tool.dart';
export 'pen/eraser_config.dart';
export 'pen/pen_config.dart';
export 'pen/pen_defaults.dart';
export 'shapes/shape_fill.dart';
export 'shapes/shape_kind.dart';
export 'tools/laser_config.dart';

/// Current tool selection, per-pen customisation and input preferences.
///
/// With a [store], customisation is restored on creation and saved
/// (debounced) whenever it changes.
class ToolSettings extends ChangeNotifier {
  ToolSettings({
    this._stylusOnly,
    this._penButtonErases = false,
    this._holdToStraighten = true,
    this._scribbleToErase = true,
    this._store,
  }) {
    final store = _store;
    if (store == null) return;
    final json = store.toolPrefs;
    if (json != null) _restore(json);
  }

  final SettingsRepository? _store;
  Timer? _saveTimer;

  EditorTool _tool = EditorTool.pen;
  final Map<InkTool, PenConfig> _configs = {for (final t in inks) t: PenConfig.defaultsFor(t)};
  EraserConfig _eraser = const EraserConfig();
  ShapeKind _shape = ShapeKind.rectangle;
  ShapeFill _shapeFill = ShapeFill.none;
  LaserConfig _laser = const LaserConfig();
  TextData _text = const TextData();
  bool _holdToStraighten;
  bool _scribbleToErase;
  List<int> _recent = const [];

  /// The tools used, most recent first: [tool], then the ones before it.
  List<EditorTool> _used = const [EditorTool.pen];
  bool? _stylusOnly;
  bool _penButtonErases;

  /// The inks offered in the toolbar: the pen (ballpoint) and highlighter.
  static const List<InkTool> inks = [InkTool.ballpoint, InkTool.highlighter];

  EditorTool get tool => _tool;
  set tool(EditorTool value) {
    if (value == _tool) return;
    _select(value);
    notifyListeners();
  }

  void _select(EditorTool value) {
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
  /// from tools that draw no ink).
  void selectColor(int index) {
    if (index < 0 || index >= activeConfig.colors.length) return;
    _leaveNonInk();
    updateConfig(activeInk, (c) => c.copyWith(colorIndex: index));
  }

  /// Selects width slot [index] of the active ink (switching to the pen
  /// from tools that draw no ink).
  void selectWidth(int index) {
    if (index < 0 || index >= activeConfig.widths.length) return;
    _leaveNonInk();
    updateConfig(activeInk, (c) => c.copyWith(widthIndex: index));
  }

  /// Steps the active ink's width selection by [delta] slots, clamped.
  void stepWidth(int delta) {
    final c = activeConfig;
    selectWidth((c.widthIndex + delta).clamp(0, c.widths.length - 1));
  }

  void _leaveNonInk() {
    if (!_tool.usesInk) _select(EditorTool.pen);
  }

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
    notifyListeners();
  }

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
    _text = other._text;
    _recent = other._recent;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persistence

  /// The persisted customisation.
  Map<String, Object?> toJson() => {
    'pens': {for (final e in _configs.entries) e.key.name: e.value.toJson()},
    'eraser': _eraser.toJson(),
    'recent': _recent,
    'shape': _shape.name,
    'shapeFill': _shapeFill.toJson(),
    'laser': _laser.toJson(),
    'text': _text.toJson(),
  };

  void _restore(String json) {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      return;
    }
    if (data is! Map) return;
    // Strict: a part that is missing or invalid keeps its defaults.
    if (data['pens'] case final Map<String, Object?> pens) {
      for (final tool in inks) {
        if (PenConfig.fromJson(pens[tool.name], tool: tool) case final config?) {
          _configs[tool] = config;
        }
      }
    }
    if (EraserConfig.fromJson(data['eraser']) case final eraser?) _eraser = eraser;
    if (RecentColors.parse(data['recent']) case final recent?) _recent = recent;
    _shape = ShapeKind.parse(data['shape']);
    _shapeFill = ShapeFill.parse(data['shapeFill']);
    _laser = LaserConfig.fromJson(data['laser']);
    if (data['text'] case final Map<String, Object?> text) _text = TextData.fromJson(text);
  }

  void _changed() {
    notifyListeners();
    if (_store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _store?.toolPrefs = jsonEncode(toJson());
  }

  @override
  void dispose() {
    if (_saveTimer != null) _save();
    super.dispose();
  }
}
