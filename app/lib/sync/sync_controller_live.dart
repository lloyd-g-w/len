part of 'sync_controller.dart';

/// Near-live sync: a run soon after local writes, a pull soon after the
/// server says another device pushed ([LiveEvents]), retries backing off
/// after failures. (State lives in [SyncController].)
extension _LiveSync on SyncController {
  /// Whether the event stream should be open: started, configured, not
  /// waiting for a new token, and the app in the foreground.
  void _updateLive() {
    _live.run = _started && !_disposed && _foreground && isConfigured && !waitsForSettings;
  }

  /// The database committed: if rows were marked for upload since, push
  /// them once writing pauses for [SyncController.writeDelay] (or after
  /// [SyncController.writeMaxDelay] of writing without a pause).
  void _onCommit() {
    if (_disposed || !_started || !isConfigured) return;
    final count = engine.dirtyWrites.count;
    if (count == _t.seenWrites) return;
    _t.seenWrites = count;
    _t.writeTimer?.cancel();
    _t.writeTimer = Timer(writeDelay, _writesDue);
    _t.writeDeadline ??= Timer(writeMaxDelay, _writesDue);
  }

  void _writesDue() {
    _t.writeTimer?.cancel();
    _t.writeDeadline?.cancel();
    _t
      ..writeTimer = null
      ..writeDeadline = null;
    _t.pushDue = true;
    _due();
  }

  /// The event stream (re)connected: if the last run failed, the server is
  /// back, so try again now rather than after the backoff.
  void _onLive() {
    if (_disposed || _state != SyncState.error || waitsForSettings) return;
    _t.cooldown?.cancel();
    _t.cooldown = null;
    _t.dueAfterCooldown = false;
    unawaited(syncInBackground());
  }

  /// The server's feed moved on: pull after [SyncController.remoteDelay]
  /// (events coming in a burst make one run), unless this device knows the
  /// change already (it pushed it).
  void _onServerEvent(ServerEvent event) {
    if (_disposed || !_isNews(event)) return;
    _t.heard = event;
    _t.remoteTimer?.cancel();
    _t.remoteTimer = Timer(remoteDelay, () {
      _t.remoteTimer = null;
      _due();
    });
  }

  /// Whether [event] tells of changes this device has not got: a newer seq,
  /// or another server id (the server lost its history).
  bool _isNews(ServerEvent event) =>
      event.serverId != settings.syncServerId || event.seq > engine.knownSeq;

  /// A run may be due: starts one if there is something to do and nothing
  /// holds it back (a run under way: decided again after it; a failure:
  /// after its backoff).
  void _due() {
    if (_disposed || !_started || !isConfigured || waitsForSettings) return;
    if (_running != null || _queued != null) {
      _t.dueAfterRun = true;
      return;
    }
    if (_t.cooldown != null) {
      _t.dueAfterCooldown = true;
      return;
    }
    if (_wanted()) {
      unawaited(syncNow());
    }
  }

  /// Whether a run has something to do: a server event not caught up with,
  /// or local writes due for upload ([_t.pushDue]: writing paused) that dirtied
  /// rows since the last run began, which are still dirty.
  bool _wanted() {
    if (_t.heard case final event? when _isNews(event)) return true;
    _t.heard = null;
    if (!_t.pushDue) return false;
    if (engine.dirtyWrites.count != _t.writesAtRunStart && _hasDirtyRows()) return true;
    _t.pushDue = false;
    return false;
  }

  /// Whether rows wait for upload; false if the database can't say (sync
  /// reports database errors itself).
  bool _hasDirtyRows() {
    try {
      return !engine.database.isClosed && engine.hasDirtyRows();
    } catch (e) {
      debugPrint('Sync: cannot look for rows to upload: $e');
      return false;
    }
  }

  /// A run begins: it pushes everything dirty now.
  void _runStarts() {
    _t.quietTicks = 0;
    _t.restartWrites = _t.writesAtRunStart;
    _t.restartPush = _t.pushDue;
    _t.pushDue = false;
    _t.writesAtRunStart = _started ? engine.dirtyWrites.count : 0;
  }

  /// A run ended (and nothing runs now): backs off after a failure (rows
  /// still dirty or an event still unanswered are tried again then), and
  /// starts what became due meanwhile.
  void _runEnded({required bool failed}) {
    if (_disposed) return;
    if (failed) {
      // What the run was to push is still to do.
      _t
        ..writesAtRunStart = _t.restartWrites
        ..pushDue = _t.pushDue || _t.restartPush || _hasDirtyRows();
      final step = SyncController.firstRetry * (1 << min(_t.failures, 8));
      _t.failures++;
      _t.cooldown?.cancel();
      _t.cooldown = Timer(step > SyncController.lastRetry ? SyncController.lastRetry : step, () {
        _t.cooldown = null;
        if (_t.dueAfterCooldown) {
          _t.dueAfterCooldown = false;
          _due();
        }
      });
      _t.dueAfterCooldown = true;
    } else {
      _t.failures = 0;
    }
    if (_t.dueAfterRun) {
      _t.dueAfterRun = false;
      _due();
    }
  }

  /// The fallback timer ticked: a run every [SyncController.interval], or
  /// every [SyncController.liveInterval] while the event stream is healthy.
  void _tick() {
    if (_live.healthy &&
        _state != SyncState.error &&
        ++_t.quietTicks * interval.inMilliseconds < liveInterval.inMilliseconds) {
      return;
    }
    unawaited(syncInBackground());
  }
}

/// The state of [_LiveSync].
class _Triggers {
  StreamSubscription<void>? commits;

  /// [SyncEngine.dirtyWrites] when last looked at, when the run under way
  /// (or the last one) began, and before that (restored if it failed).
  int seenWrites = 0;
  int writesAtRunStart = 0;
  int restartWrites = 0;

  /// Pushing local writes: after a pause, at the latest after a while;
  /// then due ([pushDue]) until a run begins (again after it failed).
  Timer? writeTimer;
  Timer? writeDeadline;
  bool pushDue = false;
  bool restartPush = false;

  /// The newest server event this device may not have caught up with.
  ServerEvent? heard;
  Timer? remoteTimer;

  /// A run became due while one was under way, or during [cooldown].
  bool dueAfterRun = false;
  bool dueAfterCooldown = false;

  /// Failed runs in a row, and the backoff after the last.
  int failures = 0;
  Timer? cooldown;

  /// Fallback timer ticks skipped since the last run.
  int quietTicks = 0;

  /// Another configuration: no backoff, no event of the old server.
  void reset() {
    failures = 0;
    cooldown?.cancel();
    cooldown = null;
    dueAfterCooldown = false;
    heard = null;
    remoteTimer?.cancel();
    remoteTimer = null;
  }

  void dispose() {
    writeTimer?.cancel();
    writeDeadline?.cancel();
    remoteTimer?.cancel();
    cooldown?.cancel();
    unawaited(commits?.cancel());
  }
}
