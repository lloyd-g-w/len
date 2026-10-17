part of 'tool_settings.dart';

/// [ToolSettings]' state and its persistence: restored from the store on
/// creation and saved (debounced) whenever the customisation changes.
abstract class _ToolState extends ChangeNotifier {
  _ToolState(
    this._stylusOnly,
    this._penButtonErases,
    this._holdToStraighten,
    this._scribbleToErase,
    this._store,
  ) {
    final store = _store;
    if (store == null) return;
    final json = store.toolPrefs;
    if (json != null) _restore(json);
  }

  final SettingsRepository? _store;
  Timer? _saveTimer;

  EditorTool _tool = EditorTool.pen;
  final Map<InkTool, PenConfig> _configs = {
    for (final t in ToolSettings.inks) t: PenConfig.defaultsFor(t),
  };
  EraserConfig _eraser = const EraserConfig();
  ShapeKind _shape = ToolSettings.defaultShape;
  ShapeFill _shapeFill = ToolSettings.defaultShapeFill;
  LaserConfig _laser = const LaserConfig();
  LassoConfig _lasso = const LassoConfig();
  TextData _text = const TextData();
  bool _holdToStraighten;
  bool _scribbleToErase;
  List<int> _recent = const [];

  /// The tools used, most recent first: [tool], then the ones before it.
  List<EditorTool> _used = const [EditorTool.pen];
  bool? _stylusOnly;
  bool _penButtonErases;
  bool _reading = false;

  /// The persisted customisation.
  Map<String, Object?> toJson() => {
    'version': ToolSettings.prefsVersion,
    'pens': {for (final e in _configs.entries) e.key.name: e.value.toJson()},
    'eraser': _eraser.toJson(),
    'recent': _recent,
    'shape': _shape.name,
    'shapeFill': _shapeFill.toJson(),
    'laser': _laser.toJson(),
    'lasso': _lasso.toJson(),
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
      for (final tool in ToolSettings.inks) {
        if (PenConfig.fromJson(pens[tool.name], tool: tool) case final config?) {
          _configs[tool] = config;
        }
      }
    }
    final version = data['version'];
    if (version is! int || version < ToolSettings.prefsVersion) _upgrade();
    if (EraserConfig.fromJson(data['eraser']) case final eraser?) _eraser = eraser;
    if (RecentColors.parse(data['recent']) case final recent?) _recent = recent;
    _shape = ShapeKind.parse(data['shape']);
    _shapeFill = ShapeFill.parse(data['shapeFill']);
    _laser = LaserConfig.fromJson(data['laser']);
    _lasso = LassoConfig.fromJson(data['lasso']);
    if (data['text'] case final Map<String, Object?> text) _text = TextData.fromJson(text);
  }

  /// Settings saved before [ToolSettings.prefsVersion] 2 had the pen's
  /// stabiliser off by default: a pen still off then gets the new default
  /// (any other stabiliser is kept; saved again, the settings are current).
  void _upgrade() {
    const pen = InkTool.ballpoint;
    final config = _configs[pen]!;
    if (config.streamline == 0) {
      _configs[pen] = config.copyWith(streamline: PenDefaults.pen.streamline);
    }
  }

  /// The customisation changed: an option chosen (a quick slot, a size, a
  /// colour) starts writing too.
  void _changed() {
    _reading = false;
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
}
