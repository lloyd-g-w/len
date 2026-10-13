import 'dart:async';

import 'package:flutter/foundation.dart';

/// An exclusive lock shared by the app's browser tabs (a Web Lock).
abstract interface class TabLock {
  /// Requests the lock and completes with whether it was granted: at once
  /// (false if another tab holds it) when [ifAvailable], else once it is
  /// free (requests are granted in order).
  Future<bool> request({bool ifAvailable = false});

  /// Releases the lock (after it was granted).
  void release();
}

/// Messages between the app's tabs (a BroadcastChannel; a tab doesn't get
/// its own messages).
abstract interface class TabChannel {
  void post(String message);

  set onMessage(void Function(String message) handler);
}

/// What a tab waiting for the lock shows.
enum WaitState {
  /// Another tab has Len open.
  waiting,

  /// "Use here" asked the other tab to hand over.
  asking,

  /// The other tab can't save its changes (storage full), so it keeps them.
  refused,

  /// The other tab didn't answer (frozen in the background, or busy).
  noAnswer,
}

/// One tab at a time owns the database; another tab can take it over
/// ("Use here"):
///
/// 1. The waiting tab B queues for the lock and posts `take:B`.
/// 2. The holder runs [onHandOver]: it stops writing and stores everything.
///    Only then does it release the lock and post `released:B`; if it
///    can't store its changes it keeps the lock (and its data) and posts
///    `refused:B`. Until storing has finished nobody else can get the lock,
///    so no interleaving can lose or overwrite data.
/// 3. The lock goes to the next queued tab. If that is not B (several tabs
///    were waiting), it releases it again at once — before opening
///    anything — and queues behind B.
/// 4. The new holder posts `holding:<id>`.
class TabHandover {
  TabHandover({
    required this.lock,
    required this.channel,
    required this.id,
    this.answerTimeout = const Duration(seconds: 5),
    this.yieldTimeout = const Duration(seconds: 10),
  }) {
    channel.onMessage = _received;
  }

  final TabLock lock;
  final TabChannel channel;

  /// This tab's id (random).
  final String id;

  /// How long "Use here" waits for the holder before [WaitState.noAnswer].
  final Duration answerTimeout;

  /// How long another tab's "Use here" makes this tab give way to it.
  final Duration yieldTimeout;

  /// What this tab shows while it waits.
  final ValueNotifier<WaitState> state = ValueNotifier(WaitState.waiting);

  bool _holding = false;
  bool _handingOver = false;
  String? _takeRequest; // A tab that asked this holder to hand over.
  String? _yieldTo; // Another waiting tab that asked to take over.
  Timer? _yieldTimer;
  Timer? _answerTimer;

  /// Whether this tab holds the lock.
  bool get holding => _holding;

  /// Run by the holder when another tab asks for the data: stop writing
  /// and store everything; complete with whether it is all stored (then
  /// the lock goes to the other tab and [onHandedOver] runs).
  Future<bool> Function()? get onHandOver => _onHandOver;
  Future<bool> Function()? _onHandOver;
  set onHandOver(Future<bool> Function()? handler) {
    _onHandOver = handler;
    if (_takeRequest case final from?) unawaited(_handOver(from));
  }

  /// Runs once this tab has handed the data to another tab.
  void Function()? onHandedOver;

  /// Completes once this tab holds the lock; calls [onWaiting] first if
  /// another tab holds it.
  Future<void> claim({required void Function() onWaiting}) async {
    if (!await lock.request(ifAvailable: true)) {
      onWaiting();
      while (true) {
        await lock.request();
        if (_yieldTo == null) break;
        // Another waiting tab asked for it: let that tab have it.
        lock.release();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    _answerTimer?.cancel();
    _holding = true;
    channel.post('holding:$id');
  }

  /// "Use here": asks the holder to hand over.
  void useHere() {
    if (_holding) return;
    _yieldTo = null;
    state.value = WaitState.asking;
    channel.post('take:$id');
    _answerTimer?.cancel();
    _answerTimer = Timer(answerTimeout, () {
      if (!_holding && state.value == WaitState.asking) state.value = WaitState.noAnswer;
    });
  }

  void _received(String message) {
    final separator = message.indexOf(':');
    if (separator < 0) return;
    final kind = message.substring(0, separator);
    final from = message.substring(separator + 1);
    switch (kind) {
      case 'take' when _holding:
        _takeRequest = from;
        unawaited(_handOver(from));
      case 'take' when from != id:
        _yieldTo = from;
        state.value = WaitState.waiting;
        _yieldTimer?.cancel();
        _yieldTimer = Timer(yieldTimeout, () => _yieldTo = null);
      case 'holding' when from == _yieldTo:
        _yieldTo = null;
      case 'refused' when from == id:
        _answerTimer?.cancel();
        state.value = WaitState.refused;
      case 'refused' when from == _yieldTo:
        _yieldTo = null;
      case 'released' when from == id:
        _answerTimer?.cancel(); // The lock is on its way.
    }
  }

  Future<void> _handOver(String to) async {
    final stop = _onHandOver;
    if (stop == null || _handingOver || !_holding) return; // Runs once the app is ready.
    _handingOver = true;
    _takeRequest = null;
    bool stored;
    try {
      stored = await stop();
    } on Object catch (error) {
      debugPrint('Handing over failed: $error');
      stored = false;
    }
    if (!stored) {
      _handingOver = false;
      channel.post('refused:$to');
      return;
    }
    _holding = false;
    lock.release();
    channel.post('released:$to');
    onHandedOver?.call();
  }
}
