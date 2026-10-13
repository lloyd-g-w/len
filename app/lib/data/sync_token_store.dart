import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../platform/secure_store.dart';
import 'settings_repository.dart';

/// The sync access token, kept in the platform's [SecureStore] under this
/// installation's slot ([SettingsRepository.syncTokenSlot]).
///
/// When the secure store fails (no keyring in a Linux session, a locked
/// one), sync must not stop: the token is kept in the database instead
/// ([SettingsRepository.syncTokenFallback], [inDatabase]) and moved to the
/// secure store at the next [load] or [retryIfDue]. A token found in the
/// database at start (one saved by an older build, too) moves the same way.
/// Without a secure store (a browser) the token lives in the database.
class SyncTokenStore extends ChangeNotifier {
  SyncTokenStore(this._settings, this._secure, {this.clock = const Clock()});

  final SettingsRepository _settings;
  final SecureStore? _secure;

  /// Times retries and names the slot.
  final Clock clock;

  /// How long after a failed attempt the secure store is tried again.
  static const retryAfter = Duration(hours: 1);

  late String _token = _settings.syncTokenFallback ?? '';
  bool _needsRetry = false;
  int _lastAttemptMs = 0;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// The token ('' when none), current right after [save]; the secure
  /// store's copy is read by [load].
  String get token => _token;

  /// Whether the token is kept in the database because the secure store
  /// failed (never in a browser, where the database is the only place).
  bool get inDatabase => _secure != null && (_settings.syncTokenFallback ?? '').isNotEmpty;

  /// Reads the token from the secure store, first moving one kept in the
  /// database there. Never throws: on failure the token stays where it is
  /// and [retryIfDue] tries again later.
  Future<void> load() => _serialized(() async {
    final secure = _secure;
    if (secure == null) return;
    _lastAttemptMs = clock.nowMs();
    final fallback = _settings.syncTokenFallback;
    try {
      if (fallback != null && fallback.isNotEmpty) {
        await secure.write(_key(), fallback);
        _settings.syncTokenFallback = null;
      } else if (_settings.syncTokenSlot case final slot?) {
        _update(await secure.read(_keyOf(slot)) ?? '');
      }
      _needsRetry = false;
    } on Object catch (e) {
      debugPrint('Secure store unavailable, sync token kept in the database: $e');
      _needsRetry = true;
    }
    notifyListeners();
  });

  /// Calls [load] again if the last attempt failed [retryAfter] ago or
  /// longer (not every sync: a locked keyring may ask to be unlocked).
  Future<void> retryIfDue() async {
    if (_needsRetry && clock.nowMs() - _lastAttemptMs >= retryAfter.inMilliseconds) await load();
  }

  /// Stores [token] ('' forgets it), in the secure store if it works, else
  /// in the database. [token] is current at once.
  Future<void> save(String token) {
    _update(token);
    return _serialized(() async {
      final secure = _secure;
      if (secure == null) {
        _settings.syncTokenFallback = token.isEmpty ? null : token;
        return;
      }
      _lastAttemptMs = clock.nowMs();
      try {
        if (token.isEmpty) {
          final slot = _settings.syncTokenSlot;
          // A new slot next time, so an entry that can't be deleted now is
          // never read again.
          _settings.syncTokenSlot = null;
          if (slot != null) await secure.delete(_keyOf(slot));
        } else {
          await secure.write(_key(), token);
        }
        _settings.syncTokenFallback = null;
        _needsRetry = false;
      } on Object catch (e) {
        debugPrint('Secure store unavailable, sync token kept in the database: $e');
        _settings.syncTokenFallback = token.isEmpty ? null : token;
        _needsRetry = token.isNotEmpty;
      }
      notifyListeners();
    });
  }

  void _update(String token) {
    if (token == _token) return;
    _token = token;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The key of this installation's slot, created if needed.
  String _key() => _keyOf(_settings.syncTokenSlot ??= clock.newId());

  static String _keyOf(String slot) => 'len.sync_token.$slot';

  /// Runs [action] after those before it (a save never races a load).
  Future<void> _serialized(Future<void> Function() action) {
    final done = _queue.then((_) => action());
    _queue = done.catchError((Object _) {});
    return done;
  }
}
