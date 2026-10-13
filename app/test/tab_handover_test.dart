import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/platform/tab_handover.dart';

/// One browser's Web Locks: one holder, requests granted in order.
class _Locks {
  _FakeLock? holder;
  final List<(_FakeLock, Completer<bool>)> queue = [];

  void _grantNext() {
    if (holder != null || queue.isEmpty) return;
    final (lock, granted) = queue.removeAt(0);
    holder = lock;
    scheduleMicrotask(() => granted.complete(true));
  }
}

class _FakeLock implements TabLock {
  _FakeLock(this._locks);

  final _Locks _locks;

  @override
  Future<bool> request({bool ifAvailable = false}) {
    if (_locks.holder == null && _locks.queue.isEmpty) {
      _locks.holder = this;
      return Future.value(true);
    }
    if (ifAvailable) return Future.value(false);
    final granted = Completer<bool>();
    _locks.queue.add((this, granted));
    return granted.future;
  }

  @override
  void release() {
    if (_locks.holder != this) return;
    _locks.holder = null;
    _locks._grantNext();
  }

  /// The tab closed: the browser releases its lock and drops its requests.
  void closeTab() {
    _locks.queue.removeWhere((r) => r.$1 == this);
    release();
  }
}

/// A BroadcastChannel: asynchronous delivery to every other tab.
class _Bus {
  final List<_FakeChannel> channels = [];
}

class _FakeChannel implements TabChannel {
  _FakeChannel(this._bus) {
    _bus.channels.add(this);
  }

  final _Bus _bus;
  void Function(String)? _handler;

  @override
  void post(String message) {
    for (final other in _bus.channels) {
      if (other != this) Timer.run(() => other._handler?.call(message));
    }
  }

  @override
  set onMessage(void Function(String message) handler) => _handler = handler;
}

/// A tab running the handover protocol, with a log of what it did.
class _Tab {
  _Tab(this.name, _Locks locks, _Bus bus, this.log, {bool reclaim = false})
    : lock = _FakeLock(locks),
      handover = null {
    handover = TabHandover(
      lock: lock,
      channel: _FakeChannel(bus),
      id: name,
      answerTimeout: const Duration(milliseconds: 100),
      yieldTimeout: const Duration(seconds: 2),
      returnGrace: const Duration(milliseconds: 100),
      reclaim: reclaim,
      onHoldingChanged: (holding) => log.add('$name holding: $holding'),
    )..onHandedOver = () => log.add('$name handed over');
  }

  final String name;
  final _FakeLock lock;
  final List<String> log;
  late TabHandover? handover;
  bool waited = false;
  bool started = false;

  TabHandover get h => handover!;

  Future<void> claim() async {
    await h.claim(onWaiting: () => waited = true);
    started = true;
    log.add('$name started');
  }

  /// Makes this tab hand over after [saving] (whether its data is stored).
  void canHandOver({bool stored = true}) => h.onHandOver = () async {
    log.add('$name saving');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    log.add('$name saved: $stored');
    return stored;
  };
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 400));

/// A test on fake time: the protocol's timeouts (100 ms here) and the
/// waits between steps are exact, however busy the machine is.
void _test(String description, Future<void> Function() body) => test(description, () {
  FakeAsync().run((async) {
    var done = false;
    Object? error;
    StackTrace? stack;
    body().then(
      (_) => done = true,
      onError: (Object e, StackTrace s) {
        (error, stack, done) = (e, s, true);
      },
    );
    for (var i = 0; i < 10000 && !done; i++) {
      async.elapse(const Duration(milliseconds: 10));
    }
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    expect(done, isTrue, reason: 'still running after 100 s of fake time');
  });
});

void main() {
  late _Locks locks;
  late _Bus bus;
  late List<String> log;

  setUp(() {
    locks = _Locks();
    bus = _Bus();
    log = [];
  });

  _Tab tab(String name, {bool reclaim = false}) => _Tab(name, locks, bus, log, reclaim: reclaim);
  List<String> started() => log.where((e) => e.endsWith('started')).toList();

  _test('the first tab starts; a second one waits', () async {
    final a = tab('a');
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    expect(a.started, isTrue);
    expect(b.waited, isTrue);
    expect(b.started, isFalse);
    expect(b.h.state.value, WaitState.waiting);
  });

  _test('Use here: the holder saves and stops before the new tab starts', () async {
    final a = tab('a')..canHandOver();
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    b.h.useHere();
    expect(b.h.state.value, WaitState.asking);
    await _settle();
    expect(log, [
      'a holding: true',
      'a started',
      'a saving',
      'a saved: true',
      'a holding: false',
      'a handed over',
      'b holding: true',
      'b started',
    ]);
    expect(locks.holder, b.lock);
    expect(a.h.holding, isFalse);
    expect(b.h.holding, isTrue);
  });

  _test('a holder that cannot save keeps the lock and says so', () async {
    final a = tab('a')..canHandOver(stored: false);
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    b.h.useHere();
    await _settle();
    expect(b.h.state.value, WaitState.refused);
    expect(b.started, isFalse);
    expect(locks.holder, a.lock);
    // Space freed: trying again works.
    a.canHandOver();
    b.h.useHere();
    await _settle();
    expect(b.started, isTrue);
  });

  _test('a holder still starting hands over once it is ready', () async {
    final a = tab('a');
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    b.h.useHere();
    await _settle();
    expect(b.h.state.value, WaitState.noAnswer);
    a.canHandOver();
    await _settle();
    expect(b.started, isTrue);
  });

  _test('with several tabs waiting, the one that asked gets it', () async {
    final a = tab('a')..canHandOver();
    await a.claim();
    final b = tab('b');
    unawaited(b.claim()); // Queued first.
    final c = tab('c');
    unawaited(c.claim());
    await _settle();
    c.h.useHere();
    await _settle();
    expect(c.started, isTrue);
    expect(b.started, isFalse);
    expect(locks.holder, c.lock);
    // b still waits, and can take over from c in turn.
    c.canHandOver();
    b.h.useHere();
    await _settle();
    expect(b.started, isTrue);
    expect(started(), ['a started', 'c started', 'b started']);
  });

  _test('closing the holder lets a waiting tab start', () async {
    final a = tab('a');
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    a.lock.closeTab();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(b.started, isFalse, reason: 'gives a reload of the holder a moment first');
    await _settle();
    expect(b.started, isTrue);
  });

  _test('a reload of the holder takes it back from a waiting tab', () async {
    final a = tab('a');
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    a.lock.closeTab(); // The reload unloads the page, releasing the lock.
    final reloaded = tab('a2', reclaim: true);
    unawaited(reloaded.claim());
    await _settle();
    expect(reloaded.started, isTrue);
    expect(reloaded.waited, isFalse);
    expect(b.started, isFalse);
    expect(locks.holder, reloaded.lock);
  });

  _test('a slow reload of the holder takes it back once the other tab saved', () async {
    final a = tab('a');
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    a.lock.closeTab();
    await _settle(); // b started meanwhile.
    b.canHandOver();
    final reloaded = tab('a2', reclaim: true);
    unawaited(reloaded.claim());
    await _settle();
    expect(started(), ['a started', 'b started', 'a2 started']);
    expect(log, containsAllInOrder(['b saved: true', 'b handed over', 'a2 started']));
    expect(locks.holder, reloaded.lock);
  });

  _test('a second request while handing over is ignored', () async {
    final a = tab('a')..canHandOver();
    await a.claim();
    final b = tab('b');
    unawaited(b.claim());
    await _settle();
    b.h.useHere();
    b.h.useHere();
    await _settle();
    expect(log.where((e) => e == 'a saving'), hasLength(1));
    expect(b.started, isTrue);
  });
}
