import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../domain/stroke.dart';
import 'pen/eraser_config.dart';
import 'pen/pen_config.dart';

export 'pen/eraser_config.dart';
export 'pen/pen_config.dart';
export 'pen/pen_defaults.dart';

/// The tools selectable in the editor toolbar.
enum EditorTool { pen, highlighter, eraser }

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
  bool _holdToStraighten = true;
  List<int> _favorites = const [];
  bool? _stylusOnly;

  static const int maxFavorites = 16;

  /// The inks offered in the toolbar: the pen (ballpoint) and highlighter.
  static const List<InkTool> inks = [InkTool.ballpoint, InkTool.highlighter];

  EditorTool get tool => _tool;
  set tool(EditorTool value) {
    if (value == _tool) return;
    _tool = value;
    notifyListeners();
  }

  /// The ink the colour/width controls currently edit: the highlighter
  /// while it is the tool, else the pen.
  InkTool get activeInk =>
      _tool == EditorTool.highlighter ? InkTool.highlighter : InkTool.ballpoint;

  /// The customisation of [tool] (the pen's for any non-highlighter ink).
  PenConfig configOf(InkTool tool) => _configs[_inkOf(tool)]!;

  /// The customisation of [activeInk].
  PenConfig get activeConfig => configOf(activeInk);

  /// Replaces the configuration of [tool].
  void updateConfig(InkTool tool, PenConfig Function(PenConfig) update) {
    _configs[_inkOf(tool)] = update(configOf(tool));
    _changed();
  }

  /// The style a new stroke with [tool] gets.
  StrokeStyle styleFor(InkTool tool) {
    final config = configOf(tool);
    return config.styleFor(_inkOf(tool), config.width);
  }

  static InkTool _inkOf(InkTool tool) =>
      tool.isHighlighter ? InkTool.highlighter : InkTool.ballpoint;

  /// Selects colour slot [index] of the active ink (leaving the eraser).
  void selectColor(int index) {
    if (index < 0 || index >= activeConfig.colors.length) return;
    _leaveEraser();
    updateConfig(activeInk, (c) => c.copyWith(colorIndex: index));
  }

  /// Selects width slot [index] of the active ink (leaving the eraser).
  void selectWidth(int index) {
    if (index < 0 || index >= activeConfig.widths.length) return;
    _leaveEraser();
    updateConfig(activeInk, (c) => c.copyWith(widthIndex: index));
  }

  /// Steps the active ink's width selection by [delta] slots, clamped.
  void stepWidth(int delta) {
    final c = activeConfig;
    selectWidth((c.widthIndex + delta).clamp(0, c.widths.length - 1));
  }

  void _leaveEraser() {
    if (_tool == EditorTool.eraser) _tool = EditorTool.pen;
  }

  EraserConfig get eraser => _eraser;
  set eraser(EraserConfig value) {
    _eraser = value;
    _changed();
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

  /// Palm rejection: only the stylus draws; fingers navigate. `null` means
  /// undecided — it turns on automatically when a stylus is first used.
  bool? get stylusOnly => _stylusOnly;
  set stylusOnly(bool? value) {
    if (value == _stylusOnly) return;
    _stylusOnly = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persistence

  /// The persisted customisation (favourites are stored separately).
  Map<String, Object?> toJson() => {
    'pens': {for (final e in _configs.entries) e.key.name: e.value.toJson()},
    'eraser': _eraser.toJson(),
    'straighten': _holdToStraighten,
  };

  void _restore(String json) {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      return;
    }
    if (data is! Map) return;
    final pens = data['pens'];
    if (pens is Map) {
      for (final tool in inks) {
        _configs[tool] = PenConfig.fromJson(
          _saved(pens, tool, data['penType']),
          _configs[tool]!,
          tool: tool,
        );
      }
    }
    _eraser = EraserConfig.fromJson(data['eraser']);
    if (data['straighten'] case final bool straighten) _holdToStraighten = straighten;
  }

  /// The saved config of [tool]. Settings from before the pen line-up was
  /// reduced to one pen take the quick colours and widths of the pen type
  /// that was in use ([penType]: fountain, brush, …) for the pen.
  static Object? _saved(Map<Object?, Object?> pens, InkTool tool, Object? penType) {
    final own = pens[tool.name];
    if (tool.isHighlighter || penType is! String || penType == tool.name) return own;
    final used = pens[penType];
    if (used is! Map || (own is Map && own.containsKey('colors'))) return own;
    return {
      ...?(own is Map ? own : null),
      'presets': used['presets'],
      'selected': used['selected'],
    };
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
