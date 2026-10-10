import '../core/clock.dart';
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
