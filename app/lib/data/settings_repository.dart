import '../core/clock.dart';
import '../domain/preferences.dart';
import 'app_database.dart';

/// Small key/value store for local, non-synced settings.
class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  static const _deviceId = 'device_id';
  static const _syncUrl = 'sync_url';
  static const _syncToken = 'sync_token';
  static const _syncLastSeq = 'sync_last_seq';
  static const _stylusOnly = 'stylus_only';
  static const _toolPrefs = 'tool_prefs';
  static const _favoriteColors = 'favorite_colors';

  /// Stable per-installation id, created on first use.
  String deviceId([Clock clock = const Clock()]) {
    final existing = _get(_deviceId);
    if (existing != null) return existing;
    final id = clock.newId();
    _set(_deviceId, id);
    return id;
  }

  String get syncUrl => _get(_syncUrl) ?? '';
  set syncUrl(String value) => _set(_syncUrl, value);

  String get syncToken => _get(_syncToken) ?? '';
  set syncToken(String value) => _set(_syncToken, value);

  /// Highest server change number already pulled.
  int get syncLastSeq => int.tryParse(_get(_syncLastSeq) ?? '') ?? 0;
  set syncLastSeq(int value) => _set(_syncLastSeq, '$value');

  /// When true, only a stylus draws and fingers always pan/zoom.
  /// Null means "not decided yet": it switches on when a stylus is first seen.
  bool? get stylusOnly => switch (_get(_stylusOnly)) {
        'true' => true,
        'false' => false,
        _ => null,
      };
  set stylusOnly(bool? value) =>
      value == null ? _remove(_stylusOnly) : _set(_stylusOnly, '$value');

  /// Pen, highlighter and eraser customisation as an opaque JSON document
  /// (owned by `ToolSettings`); null until first saved.
  String? get toolPrefs => _get(_toolPrefs);
  set toolPrefs(String? value) => value == null ? _remove(_toolPrefs) : _set(_toolPrefs, value);

  /// The user's saved favourite colours (ARGB), most recent first.
  List<int> get favoriteColors => [
        for (final part in (_get(_favoriteColors) ?? '').split(','))
          if (int.tryParse(part) case final int c) c,
      ];
  set favoriteColors(List<int> colors) => _set(_favoriteColors, colors.join(','));

  // ---------------------------------------------------------------------------
  // Appearance, gestures and library view (prefer [AppPreferences], which
  // also notifies listeners).

  static const _themeMode = 'theme_mode';
  static const _accentColor = 'accent_color';
  static const _twoFingerTapUndo = 'two_finger_tap_undo';
  static const _threeFingerTapRedo = 'three_finger_tap_redo';
  static const _penButtonAction = 'pen_button_action';
  static const _libraryLayout = 'library_layout';
  static const _librarySort = 'library_sort';

  ThemePreference get themeMode => ThemePreference.parse(_get(_themeMode));
  set themeMode(ThemePreference value) => _set(_themeMode, value.name);

  /// ARGB accent (seed) colour, or null for the default.
  int? get accentColor => int.tryParse(_get(_accentColor) ?? '');
  set accentColor(int? value) =>
      value == null ? _remove(_accentColor) : _set(_accentColor, '$value');

  /// Two-finger tap undoes (default on).
  bool get twoFingerTapUndo => _get(_twoFingerTapUndo) != 'false';
  set twoFingerTapUndo(bool value) => _set(_twoFingerTapUndo, '$value');

  /// Three-finger tap redoes (default on).
  bool get threeFingerTapRedo => _get(_threeFingerTapRedo) != 'false';
  set threeFingerTapRedo(bool value) => _set(_threeFingerTapRedo, '$value');

  /// What holding the stylus side button does (default: eraser).
  PenButtonAction get penButtonAction => PenButtonAction.parse(_get(_penButtonAction));
  set penButtonAction(PenButtonAction value) => _set(_penButtonAction, value.name);

  LibraryLayout get libraryLayout => LibraryLayout.parse(_get(_libraryLayout));
  set libraryLayout(LibraryLayout value) => _set(_libraryLayout, value.name);

  LibrarySort get librarySort => LibrarySort.parse(_get(_librarySort));
  set librarySort(LibrarySort value) => _set(_librarySort, value.name);

  /// How paged notebooks are shown (`continuous` / `single`); null = default.
  String? get pageFlow => _get('page_flow');
  set pageFlow(String? value) => value == null ? _remove('page_flow') : _set('page_flow', value);

  String? _get(String key) {
    final rows = _database.db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void _set(String key, String value) => _database.db.execute(
        'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
        [key, value],
      );

  void _remove(String key) =>
      _database.db.execute('DELETE FROM settings WHERE key = ?', [key]);
}
