part of 'sync_controller.dart';

/// Live sync over the server's live connection ([LiveLink], `/v1/live`):
/// local edits pushed a moment after they are committed, other devices'
/// records applied as they arrive. Between sync runs only (a run waits for
/// live work, live work for a run); whatever it cannot do (a gap in the
/// feed, a blob to upload first, too much at once) it leaves to a run.
/// (State lives in [SyncController] and [_Socket].)
extension _SocketSync on SyncController {
  /// Whether this device may push and apply live now: greeted by the
  /// server it syncs with, which it is up to date with.
  bool get _liveReady {
    final hello = _s.hello;
    return _socket.healthy && hello != null && engine.liveReady(hello.serverId);
  }

  void _onLiveMessage(LiveMessage message) {
    if (_disposed) return;
    switch (message) {
      case LiveHello(:final serverId, :final seq):
        _s.hello = message;
        _onLive();
        _onServerEvent((seq: seq, serverId: serverId));
        if (_liveReady && _hasDirtyRows()) _scheduleLivePush(now: true);
      case LiveRecords():
        _s.inbox.add(message);
        if (_s.inbox.length > _Socket.maxInbox) _overflow();
        _drainLive();
      case LiveResync(:final seq, :final serverId):
        _onServerEvent((seq: seq, serverId: serverId ?? settings.syncServerId));
      case LivePresence() || LiveEphemeral():
        rooms.receive(message);
      case LiveHello() || LivePushed() || LiveError() || LiveOther():
    }
  }

  /// Too much waiting: a pull fetches it all.
  void _overflow() {
    final last = _s.inbox.last;
    _s.inbox.clear();
    _onServerEvent((seq: last.seq, serverId: _s.hello?.serverId ?? settings.syncServerId));
  }

  /// Applies the records that came in, in order, unless a run is under
  /// way (it calls this again when it ends). A gap (records this device
  /// never got) or a server it is not up to date with makes a run.
  void _drainLive() {
    if (_s.busy || _running != null || _s.inbox.isEmpty || _disposed) return;
    if (!_liveReady) {
      _overflow();
      return;
    }
    unawaited(
      _liveWork(() async {
        while (_s.inbox.isNotEmpty && !_disposed && _running == null) {
          final message = _s.inbox.removeFirst();
          final RemoteChanges? changes;
          try {
            changes = await engine.applyLive(message, isCancelled: () => _disposed);
          } catch (e, stack) {
            debugPrint('Sync: cannot apply live records: $e\n$stack');
            _s.inbox.add(message);
            _overflow();
            return;
          }
          if (_disposed) return;
          if (changes == null) {
            _s.inbox.addFirst(message);
            _overflow();
            return;
          }
          _s.applied++;
          if (!changes.isEmpty) _remoteChanges.add(changes);
          revivalNotices(changes, _titleOf).forEach(_notices.add);
          // Brought back by a deletion conflict: local edits to push.
          if (changes.revived) _pushSoon(now: true);
        }
      }),
    );
  }

  /// Local writes were committed: push them over the live connection a
  /// frame from now ([now]: at once), or, within
  /// [SyncController.livePushDelay] of the last push, once that has passed
  /// (writes meanwhile make one push). False if the connection cannot take
  /// them.
  bool _scheduleLivePush({bool now = false}) {
    if (!_liveReady) return false;
    if (_s.pushTimer != null) return true; // It takes these too.
    if (_s.cooling != null && !now) {
      _s.afterCooling = true;
      return true;
    }
    _s.pushTimer = Timer(now ? Duration.zero : SyncController.liveFrame, _livePushDue);
    return true;
  }

  void _livePushDue() {
    _s.pushTimer = null;
    if (_disposed) return;
    if (_running != null || _s.busy) {
      _s.pushAgain = true; // After it.
      return;
    }
    if (!_liveReady) {
      _pushSoon(); // With a run, then.
      return;
    }
    _s.cooling?.cancel();
    _s.cooling = Timer(livePushDelay, () {
      _s.cooling = null;
      if (_s.afterCooling && !_disposed) {
        _s.afterCooling = false;
        _pushSoon(now: true);
      }
    });
    unawaited(
      _liveWork(() async {
        final LivePushOutcome outcome;
        try {
          outcome = await engine.pushLive(_socket.push, isCancelled: () => _disposed);
        } catch (e, stack) {
          debugPrint('Sync: live push failed: $e\n$stack');
          _pushInRun();
          return;
        }
        _s.pushes++;
        switch (outcome) {
          case LivePushOutcome.done:
            _s.stale = 0;
          case LivePushOutcome.stale when ++_s.stale <= _Socket.maxStale:
            // The changes it lacks are on their way: apply them, then again.
            _s.pushAgain = true;
          case LivePushOutcome.stale || LivePushOutcome.needsRun:
            _s.stale = 0;
            _pushInRun();
        }
      }),
    );
  }

  /// What a live push left goes with a run, now.
  void _pushInRun() {
    _t.pushDue = true;
    _due();
  }

  /// Runs [work] as the live work under way; afterwards what came in or
  /// became due meanwhile follows (records first, then pushes).
  Future<void> _liveWork(Future<void> Function() work) async {
    _s.busy = true;
    try {
      await work();
    } finally {
      _s.busy = false;
      final idle = _s.idle;
      _s.idle = null;
      idle?.complete();
    }
    if (_disposed) return;
    if (_s.inbox.isNotEmpty) {
      _drainLive();
    } else if (_s.pushAgain) {
      _s.pushAgain = false;
      _pushSoon(now: true);
    }
  }

  /// Completes once no live work is under way (a run waits for it).
  Future<void> _liveIdle() {
    if (!_s.busy) return Future.value();
    return (_s.idle ??= Completer<void>()).future;
  }

  /// A run ended: live work held back for it goes on.
  void _liveAfterRun() {
    if (_disposed) return;
    _drainLive();
    if (_s.pushAgain && !_s.busy) {
      _s.pushAgain = false;
      _pushSoon(now: true);
    }
  }
}

/// The state of [_SocketSync].
class _Socket {
  /// Records messages waiting beyond this many make a pull instead.
  static const maxInbox = 256;

  /// Stale live pushes in a row before a run pushes instead.
  static const maxStale = 5;

  /// The greeting of the connection open now.
  LiveHello? hello;

  /// Records messages not applied yet, in order.
  final inbox = Queue<LiveRecords>();

  /// Whether live work (applying, pushing) is under way, and who waits
  /// for it to end.
  bool busy = false;
  Completer<void>? idle;

  /// A live push asked for while one ran, or a run.
  bool pushAgain = false;

  /// The push about to go, and the time after one when writes wait for the
  /// next ([afterCooling]: some did).
  Timer? pushTimer;
  Timer? cooling;
  bool afterCooling = false;
  int stale = 0;

  /// Records messages applied and live pushes made (tests).
  int applied = 0;
  int pushes = 0;

  void reset() {
    hello = null;
    inbox.clear();
    pushAgain = afterCooling = false;
    pushTimer?.cancel();
    cooling?.cancel();
    pushTimer = cooling = null;
    stale = 0;
  }

  void dispose() => reset();
}
