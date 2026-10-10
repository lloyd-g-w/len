import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../domain/stroke.dart';
import 'pen/eraser_config.dart';
import 'pen/pen_config.dart';

export 'pen/eraser_config.dart';
export 'pen/pen_config.dart';

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
    _favorites = store.favoriteColors;
  }

  final SettingsRepository? _store;
  Timer? _saveTimer;

  EditorTool _tool = EditorTool.pen;
  InkTool _penType = InkTool.ballpoint;
  final Map<InkTool, PenConfig> _configs = {
    for (final t in [...InkTool.pens, InkTool.highlighter]) t: PenConfig.defaultsFor(t),
  };
  EraserConfig _eraser = const EraserConfig();
  bool _holdToStraighten = true;
  List<int> _favorites = const [];
  bool? _stylusOnly;

  static const int maxFavorites = 16;

  EditorTool get tool => _tool;
  set tool(EditorTool value) {
    if (value == _tool) return;
    _tool = value;
    notifyListeners();
  }

  /// The pen type used by [EditorTool.pen] (one of [InkTool.pens]).
  InkTool get penType => _penType;
  set penType(InkTool value) {
    assert(InkTool.pens.contains(value));
    _penType = value;
    _tool = EditorTool.pen;
    _changed();
  }

  /// The ink tool the colour/width controls currently edit (the pen while
  /// the eraser is active).
  InkTool get activeInk => _tool == EditorTool.highlighter ? InkTool.highlighter : _penType;

  PenConfig configOf(InkTool tool) => _configs[tool] ?? PenConfig.defaultsFor(tool);
  PenConfig get activeConfig => configOf(activeInk);

  /// Replaces the configuration of [tool].
  void updateConfig(InkTool tool, PenConfig Function(PenConfig) update) {
    _configs[tool] = update(configOf(tool));
    _changed();
  }

  /// The style a new stroke with [tool] gets.
  StrokeStyle styleFor(InkTool tool) {
    final config = configOf(tool);
    return config.styleFor(tool, config.current.width);
  }

  /// Selects preset [index] of the active ink (and leaves the eraser).
  void selectPreset(int index) {
    if (_tool == EditorTool.eraser) _tool = EditorTool.pen;
    updateConfig(activeInk, (c) => c.copyWith(selected: index));
  }

  /// Replaces preset [index] of the active ink.
  void setPreset(int index, PenPreset preset) =>
      updateConfig(activeInk, (c) => c.withPreset(index, preset));

  /// Sets the colour of the active ink's selected preset; the alpha channel
  /// becomes the pen's opacity.
  void setColor(int argb) {
    if (_tool == EditorTool.eraser) _tool = EditorTool.pen;
    updateConfig(activeInk, (c) {
      return c
          .withPreset(c.selected, c.current.copyWith(color: argb | 0xFF000000))
          .copyWith(opacity: ((argb >>> 24) & 0xFF) / 255);
    });
  }

  void setWidth(double width) =>
      updateConfig(activeInk, (c) => c.withPreset(c.selected, c.current.copyWith(width: width)));

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

  void addFavorite(int argb) {
    _favorites = [argb, ..._favorites.where((c) => c != argb)].take(maxFavorites).toList();
    _store?.favoriteColors = _favorites;
    notifyListeners();
  }

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

  Map<String, Object?> toJson() => {
    'penType': _penType.name,
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
    final penType = InkTool.parse('${data['penType']}');
    if (InkTool.pens.contains(penType)) _penType = penType;
    final pens = data['pens'];
    if (pens is Map) {
      for (final tool in _configs.keys.toList()) {
        _configs[tool] = PenConfig.fromJson(pens[tool.name], _configs[tool]!);
      }
    }
    _eraser = EraserConfig.fromJson(data['eraser']);
    if (data['straighten'] case final bool straighten) _holdToStraighten = straighten;
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
