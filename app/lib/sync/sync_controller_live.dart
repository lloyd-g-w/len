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
    if (count == _seenWrites) return;
    _seenWrites = count;
    _writeTimer?.cancel();
    _writeTimer = Timer(writeDelay, _writesDue);
    _writeDeadline ??= Timer(writeMaxDelay, _writesDue);
  }

  void _writesDue() {
    _writeTimer?.cancel();
    _writeDeadline?.cancel();
    _writeTimer = _writeDeadline = null;
    _pushDue = true;
    _due();
  }

  /// The event stream (re)connected: if the last run failed, the server is
  /// back, so try again now rather than after the backoff.
  void _onLive() {
    if (_disposed || _state != SyncState.error || waitsForSettings) return;
    _cooldown?.cancel();
    _cooldown = null;
    _dueAfterCooldown = false;
    unawaited(syncInBackground());
  }

  /// The server's feed moved on: pull after [SyncController.remoteDelay]
  /// (events coming in a burst make one run), unless this device knows the
  /// change already (it pushed it).
  void _onServerEvent(ServerEvent event) {
    if (_disposed || !_isNews(event)) return;
    _heard = event;
    _remoteTimer?.cancel();
    _remoteTimer = Timer(remoteDelay, () {
      _remoteTimer = null;
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
      _dueAfterRun = true;
      return;
    }
    if (_cooldown != null) {
      _dueAfterCooldown = true;
      return;
    }
    if (_wanted()) {
      unawaited(syncNow());
    }
  }

  /// Whether a run has something to do: a server event not caught up with,
  /// or local writes due for upload ([_pushDue]: writing paused) that dirtied
  /// rows since the last run began, which are still dirty.
  bool _wanted() {
    if (_heard case final event? when _isNews(event)) return true;
    _heard = null;
    if (!_pushDue) return false;
    if (engine.dirtyWrites.count != _writesAtRunStart && engine.hasDirtyRows()) return true;
    _pushDue = false;
    return false;
  }

  /// A run begins: it pushes everything dirty now.
  void _runStarts() {
    _quietTicks = 0;
    _restartWrites = _writesAtRunStart;
    _restartPush = _pushDue;
    _pushDue = false;
    _writesAtRunStart = _started ? engine.dirtyWrites.count : 0;
  }

  /// A run ended (and nothing runs now): backs off after a failure (rows
  /// still dirty or an event still unanswered are tried again then), and
  /// starts what became due meanwhile.
  void _runEnded({required bool failed}) {
    if (_disposed) return;
    if (failed) {
      // What the run was to push is still to do.
      _writesAtRunStart = _restartWrites;
      _pushDue = _pushDue || _restartPush || engine.hasDirtyRows();
      final step = SyncController.firstRetry * (1 << min(_failures, 8));
      _failures++;
      _cooldown?.cancel();
      _cooldown = Timer(step > SyncController.lastRetry ? SyncController.lastRetry : step, () {
        _cooldown = null;
        if (_dueAfterCooldown) {
          _dueAfterCooldown = false;
          _due();
        }
      });
      _dueAfterCooldown = true;
    } else {
      _failures = 0;
    }
    if (_dueAfterRun) {
      _dueAfterRun = false;
      _due();
    }
  }

  /// The fallback timer ticked: a run every [SyncController.interval], or
  /// every [SyncController.liveInterval] while the event stream is healthy.
  void _tick() {
    if (_live.healthy &&
        _state != SyncState.error &&
        ++_quietTicks * interval.inMilliseconds < liveInterval.inMilliseconds) {
      return;
    }
    unawaited(syncInBackground());
  }
}
