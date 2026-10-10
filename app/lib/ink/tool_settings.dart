import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../domain/stroke.dart';
import '../domain/text_data.dart';
import 'pen/eraser_config.dart';
import 'pen/pen_config.dart';
import 'shapes/shape_kind.dart';

export 'pen/eraser_config.dart';
export 'pen/pen_config.dart';
export 'shapes/shape_kind.dart';

/// The tools selectable in the editor toolbar.
enum EditorTool {
  pen,
  highlighter,
  eraser,
  lasso,
  shape,
  text,
  laser;

  /// Whether the tool draws ink with the pen presets (colour and width).
  bool get usesPresets => this == pen || this == highlighter || this == shape;
}

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
  InkTool _penType = InkTool.ballpoint;
  final Map<InkTool, PenConfig> _configs = {
    for (final t in [...InkTool.pens, InkTool.highlighter]) t: PenConfig.defaultsFor(t),
  };
  EraserConfig _eraser = const EraserConfig();
  ShapeKind _shape = ShapeKind.rectangle;
  TextData _text = const TextData();
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

  /// The customisation of [tool].
  PenConfig configOf(InkTool tool) => _configs[tool] ?? PenConfig.defaultsFor(tool);

  /// The customisation of [activeInk].
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

  /// Selects preset [index] of the active ink (and switches to the pen
  /// from tools that draw no ink).
  void selectPreset(int index) {
    if (index < 0 || index >= PenConfig.presetCount) return;
    if (!_tool.usesPresets) _tool = EditorTool.pen;
    updateConfig(activeInk, (c) => c.copyWith(selected: index));
  }

  /// Replaces preset [index] of the active ink.
  void setPreset(int index, PenPreset preset) =>
      updateConfig(activeInk, (c) => c.withPreset(index, preset));

  /// Sets the colour of the active ink's selected preset; the alpha channel
  /// becomes the pen's opacity.
  void setColor(int argb) {
    if (!_tool.usesPresets) _tool = EditorTool.pen;
    updateConfig(activeInk, (c) {
      return c
          .withPreset(c.selected, c.current.copyWith(color: argb | 0xFF000000))
          .copyWith(opacity: math.max(((argb >>> 24) & 0xFF) / 255, PenConfig.minOpacity));
    });
  }

  /// Sets the width of the active ink's selected preset.
  void setWidth(double width) =>
      updateConfig(activeInk, (c) => c.withPreset(c.selected, c.current.copyWith(width: width)));

  EraserConfig get eraser => _eraser;
  set eraser(EraserConfig value) {
    _eraser = value;
    _changed();
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
    'penType': _penType.name,
    'pens': {for (final e in _configs.entries) e.key.name: e.value.toJson()},
    'eraser': _eraser.toJson(),
    'straighten': _holdToStraighten,
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
    final penType = InkTool.parse('${data['penType']}');
    if (InkTool.pens.contains(penType)) _penType = penType;
    final pens = data['pens'];
    if (pens is Map) {
      for (final tool in _configs.keys.toList()) {
        _configs[tool] = PenConfig.fromJson(pens[tool.name], _configs[tool]!, tool: tool);
      }
    }
    _eraser = EraserConfig.fromJson(data['eraser']);
    if (data['straighten'] case final bool straighten) _holdToStraighten = straighten;
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
