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

  /// The server's `blobsCollectedAt` (`/v1/health`) seen last; when it
  /// changes, the server deleted blobs and uploads are re-checked.
  int get syncBlobsCollectedAt => int.tryParse(_get('sync_blobs_collected_at') ?? '') ?? 0;
  set syncBlobsCollectedAt(int value) => _set('sync_blobs_collected_at', '$value');

  /// When (ms since epoch) local blob garbage collection last ran; 0 = never.
  int get blobGcLastRun => int.tryParse(_get('blob_gc_last_run') ?? '') ?? 0;
  set blobGcLastRun(int value) => _set('blob_gc_last_run', '$value');

  /// When true, only a stylus draws and fingers always pan/zoom.
  /// Null means "not decided yet": it switches on when a stylus is first seen.
  bool? get stylusOnly => switch (_get(_stylusOnly)) {
    'true' => true,
    'false' => false,
    _ => null,
  };
  set stylusOnly(bool? value) => value == null ? _remove(_stylusOnly) : _set(_stylusOnly, '$value');

  /// Pen, highlighter and eraser customisation as an opaque JSON document
  /// (owned by `ToolSettings`); null until first saved.
  String? get toolPrefs => _get(_toolPrefs);
  set toolPrefs(String? value) => value == null ? _remove(_toolPrefs) : _set(_toolPrefs, value);

  // ---------------------------------------------------------------------------
  // Appearance, gestures and library view (prefer [AppPreferences], which
  // also notifies listeners).

  static const _themeMode = 'theme_mode';
  static const _fingerTapUndo = 'finger_tap_undo';
  static const _penButtonAction = 'pen_button_action';
  static const _libraryLayout = 'library_layout';
  static const _librarySort = 'library_sort';

  ThemePreference get themeMode => ThemePreference.parse(_get(_themeMode));
  set themeMode(ThemePreference value) => _set(_themeMode, value.name);

  /// Two-finger tap undoes, three-finger tap redoes (default on).
  bool get fingerTapUndo => _get(_fingerTapUndo) != 'false';
  set fingerTapUndo(bool value) => _set(_fingerTapUndo, '$value');

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

  /// Where the editor toolbar sits (default: docked).
  ToolbarPlacement get toolbarPlacement => ToolbarPlacement.parse(_get('toolbar_placement'));
  set toolbarPlacement(ToolbarPlacement value) => _set('toolbar_placement', value.name);

  /// Ids of the editor's one-time tips already shown on this device.
  Set<String> get seenTips => {...?_get('tips_seen')?.split(',').where((id) => id.isNotEmpty)};
  void markTipSeen(String id) => _set('tips_seen', {...seenTips, id}.join(','));

  /// Centre of the floating toolbar as a fraction of the editor size
  /// (x, y in 0..1); null = not placed yet.
  (double, double)? get toolbarFloat {
    final parts = _get('toolbar_float')?.split(',');
    if (parts == null || parts.length != 2) return null;
    final x = double.tryParse(parts[0]), y = double.tryParse(parts[1]);
    return x == null || y == null ? null : (x, y);
  }

  set toolbarFloat((double, double)? value) =>
      value == null ? _remove('toolbar_float') : _set('toolbar_float', '${value.$1},${value.$2}');

  /// Paper styles (by name) of the latest new notebooks, most recent first.
  List<String> get recentPapers => [
    for (final part in (_get('recent_papers') ?? '').split(','))
      if (part.isNotEmpty) part,
  ];
  set recentPapers(List<String> names) => _set('recent_papers', names.join(','));

  /// Handwriting recognition language (BCP 47); null = from the device locale.
  String? get handwritingLanguage => _get('handwriting_language');
  set handwritingLanguage(String? value) =>
      value == null ? _remove('handwriting_language') : _set('handwriting_language', value);

  /// Whether handwriting is recognised in the background for search.
  bool get handwritingIndexing => _get('handwriting_indexing') != 'false';
  set handwritingIndexing(bool value) => _set('handwriting_indexing', '$value');

  /// Where the editor last looked in notebook [notebookId] (an opaque
  /// string owned by the editor), or null.
  String? editorView(String notebookId) => _get('editor_view.$notebookId');
  void setEditorView(String notebookId, String? value) =>
      value == null ? _remove('editor_view.$notebookId') : _set('editor_view.$notebookId', value);

  String? _get(String key) {
    final rows = _database.db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void _set(String key, String value) => _database.db.execute(
    'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
    [key, value],
  );

  void _remove(String key) => _database.db.execute('DELETE FROM settings WHERE key = ?', [key]);
}
