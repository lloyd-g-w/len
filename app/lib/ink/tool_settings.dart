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
import 'shapes/shape_kind.dart';

export 'editor_tool.dart';
export 'pen/eraser_config.dart';
export 'pen/pen_config.dart';
export 'pen/pen_defaults.dart';
export 'shapes/shape_kind.dart';

/// Current tool selection, per-pen customisation and input preferences.
///
/// With a [store], customisation is restored on creation and saved
/// (debounced) whenever it changes.
class ToolSettings extends ChangeNotifier {
  ToolSettings({this._stylusOnly, this._store}) {
    final store = _store;
    if (store == null) return;
    final json = store.toolPrefs;
    if (json != null) _restore(json);
    _favorites = _normalizedFavorites(store.favoriteColors);
  }

  final SettingsRepository? _store;
  Timer? _saveTimer;

  EditorTool _tool = EditorTool.pen;
  final Map<InkTool, PenConfig> _configs = {for (final t in inks) t: PenConfig.defaultsFor(t)};
  EraserConfig _eraser = const EraserConfig();
  ShapeKind _shape = ShapeKind.rectangle;
  TextData _text = const TextData();
  bool _holdToStraighten = true;
  List<int> _favorites = const [];
  List<int> _recent = const [];
  EditorTool _lastInk = EditorTool.pen;
  bool? _stylusOnly;

  static const int maxFavorites = 16;

  /// The inks offered in the toolbar: the pen (ballpoint) and highlighter.
  static const List<InkTool> inks = [InkTool.ballpoint, InkTool.highlighter];

  EditorTool get tool => _tool;
  set tool(EditorTool value) {
    if (value == _tool || (value == EditorTool.selectText && !_selectTextAvailable)) return;
    _select(value);
    notifyListeners();
  }

  void _select(EditorTool value) {
    _tool = value;
    if (value == EditorTool.pen || value == EditorTool.highlighter) _lastInk = value;
  }

  bool _selectTextAvailable = false;

  /// Whether [EditorTool.selectText] is offered: the open notebook has
  /// imported PDF pages. Turning it off leaves the tool for the pen.
  bool get selectTextAvailable => _selectTextAvailable;
  set selectTextAvailable(bool value) {
    if (value == _selectTextAvailable) return;
    _selectTextAvailable = value;
    if (!value && _tool == EditorTool.selectText) _tool = EditorTool.pen;
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

  /// Draws with [tool] (pen or highlighter) in [color] and [width] (a
  /// favourite pen): selects the quick colour and width slots holding
  /// them, or puts them into the selected slots, as picking a colour does.
  void usePreset(EditorTool tool, {required int color, required double width}) {
    final ink = tool == EditorTool.highlighter ? InkTool.highlighter : InkTool.ballpoint;
    _select(tool == EditorTool.highlighter ? tool : EditorTool.pen);
    updateConfig(ink, (c) {
      final ci = c.colors.indexOf(color);
      c = ci == -1 ? c.withColor(c.colorIndex, color) : c.copyWith(colorIndex: ci);
      final wi = c.widths.indexWhere((w) => (w - width).abs() < 1e-3);
      return wi == -1 ? c.withWidth(c.widthIndex, width) : c.copyWith(widthIndex: wi);
    });
  }

  void _leaveNonInk() {
    if (!_tool.usesInk) _select(EditorTool.pen);
  }

  /// The shape the Shape tool draws.
  ShapeKind get shape => _shape;
  set shape(ShapeKind value) {
    _shape = value;
    _tool = EditorTool.shape;
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

  /// An erase stroke made with the eraser tool ended. With
  /// [EraserConfig.autoDeselect] the ink used before it (pen or
  /// highlighter) becomes the tool again; returns whether it did.
  bool eraserStrokeEnded() {
    if (_tool != EditorTool.eraser || !_eraser.autoDeselect) return false;
    tool = _lastInk;
    return true;
  }

  /// Eraser radius in screen pixels (independent of zoom).
  double get eraserRadius => _eraser.radius;

  /// Holding the pen still at the end of a stroke straightens it.
  bool get holdToStraighten => _holdToStraighten;
  set holdToStraighten(bool value) {
    _holdToStraighten = value;
    _changed();
  }

  /// Saved favourite colours (ARGB), most recent first.
  List<int> get favorites => _favorites;

  /// Saves [argb] as the most recent favourite (moving it to the front if
  /// already saved); keeps at most [maxFavorites].
  void addFavorite(int argb) {
    _favorites = _normalizedFavorites([argb, ..._favorites]);
    _store?.favoriteColors = _favorites;
    notifyListeners();
  }

  /// Forgets favourite [argb].
  void removeFavorite(int argb) {
    _favorites = _favorites.where((c) => c != argb).toList();
    _store?.favoriteColors = _favorites;
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
    final tool = other._tool == EditorTool.selectText && !_selectTextAvailable
        ? _tool
        : other._tool;
    final same =
        tool == _tool &&
        _eraser == other._eraser &&
        _shape == other._shape &&
        identical(_text, other._text) &&
        _holdToStraighten == other._holdToStraighten &&
        identical(_recent, other._recent) &&
        inks.every((t) => identical(_configs[t], other._configs[t]));
    if (same) return;
    _tool = tool;
    _lastInk = other._lastInk;
    _configs.addAll(other._configs);
    _eraser = other._eraser;
    _shape = other._shape;
    _text = other._text;
    _holdToStraighten = other._holdToStraighten;
    _recent = other._recent;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persistence

  /// The persisted customisation (favourites are stored separately).
  Map<String, Object?> toJson() => {
    'pens': {for (final e in _configs.entries) e.key.name: e.value.toJson()},
    'eraser': _eraser.toJson(),
    'straighten': _holdToStraighten,
    'recent': _recent,
    'shape': _shape.name,
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
    if (data['straighten'] case final bool straighten) _holdToStraighten = straighten;
    if (RecentColors.parse(data['recent']) case final recent?) _recent = recent;
    _shape = ShapeKind.parse(data['shape']);
    if (data['text'] case final Map<String, Object?> text) _text = TextData.fromJson(text);
  }

  /// Distinct colours, first occurrence first, at most [maxFavorites].
  static List<int> _normalizedFavorites(Iterable<int> colors) =>
      colors.toSet().take(maxFavorites).toList(growable: false);

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
