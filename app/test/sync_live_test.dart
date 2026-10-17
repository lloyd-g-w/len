import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/sync/sync_controller.dart';

import 'support/fault_devices.dart';
import 'support/faulty_network.dart';
import 'support/real_server.dart';

// Near-live sync against the real server (`server/`) in this process, on
// fake time: a write is pushed a few seconds after writing pauses, the
// server's event stream (`/v1/events`) makes other devices pull, and
// nothing runs more than it needs to.

/// Devices on one real server, on fake time.
class _Live {
  _Live(this.async) : server = RealServer() {
    network = FaultyNetwork(server, math.Random(1));
  }

  final FakeAsync async;
  final RealServer server;
  late final FaultyNetwork network;
  final time = SharedTime();
  final devices = <FaultDevice>[];

  /// A device set up to sync, started as the app starts it.
  FaultDevice device(String prefix) {
    FaultDevice? device;
    FaultDevice.start(network, time, prefix).then((d) => device = d);
    async.flushMicrotasks();
    devices.add(device!);
    device!.s.sync.start();
    return device!;
  }

  /// Lets [duration] pass (the app clock too), a tenth of a second at a time.
  void wait(Duration duration) {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < duration; t += step) {
      time.now += step.inMilliseconds;
      async.elapse(step);
    }
  }

  /// Waits until [done] holds (at most [limit]) and returns how long it took.
  Duration until(bool Function() done, {Duration limit = const Duration(minutes: 5)}) {
    const step = Duration(milliseconds: 100);
    var waited = Duration.zero;
    while (!done()) {
      if (waited >= limit) fail('not within $limit');
      wait(step);
      waited += step;
    }
    return waited;
  }

  /// Syncs [device] now (as Sync now does) and waits until the run ended.
  void sync(FaultDevice device) {
    var done = false;
    device.s.sync.syncNow().whenComplete(() => done = true);
    until(() => done, limit: const Duration(seconds: 1));
  }

  void dispose() {
    for (final d in devices) {
      d.dispose();
    }
    server.dispose();
    async.flushMicrotasks();
  }
}

/// Counts the sync runs of [device] from now on.
_Runs _runs(FaultDevice device) => _Runs(device.s.sync);

class _Runs {
  _Runs(this.sync) : _was = sync.state {
    sync.addListener(_changed);
  }

  final SyncController sync;
  SyncState _was;
  int count = 0;

  void _changed() {
    if (sync.state == SyncState.syncing && _was != SyncState.syncing) count++;
    _was = sync.state;
  }
}

void _liveTest(String name, void Function(_Live live) body) {
  test(name, () {
    fakeAsync((async) {
      final l = _Live(async);
      try {
        body(l);
      } finally {
        l.dispose();
      }
    });
  });
}

void main() {
  _liveTest('an edit on one device reaches another within seconds', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    expect(a.s.sync.live, isTrue);
    expect(b.s.sync.live, isTrue);
    expect(l.server.events.streams, 2);
    final runsA = _runs(a);
    final runsB = _runs(b);

    final folder = a.s.folders.create(name: 'Live', color: 1);
    final took = l.until(() => b.s.folders.get(folder.id) != null);
    expect(took, lessThanOrEqualTo(const Duration(seconds: 5)));

    // One run each: A pushed (its own push's event made it pull nothing),
    // B pulled; the fallback timer waits while the stream is healthy.
    l.wait(const Duration(seconds: 100));
    expect(runsA.count, 1);
    expect(runsB.count, 1);
  });

  _liveTest('writing for a minute pushes every few seconds, not on every write', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    final runsA = _runs(a);
    final runsB = _runs(b);
    final requests = l.network.requests;
    String? last;
    for (var i = 0; i < 150; i++) {
      last = a.s.folders.create(name: 'Folder $i', color: 1).id;
      l.wait(const Duration(milliseconds: 400));
    }
    // Pushed at the latest every 10 s while writing goes on.
    expect(runsA.count, inInclusiveRange(5, 8));
    expect(runsB.count, lessThanOrEqualTo(runsA.count + 1));
    final took = l.until(() => b.s.folders.get(last!) != null);
    expect(took, lessThanOrEqualTo(const Duration(seconds: 5)));
    expect(b.s.folders.list().length, 150);
    // A few requests per run, nothing per write.
    expect(l.network.requests - requests, lessThan(100));
  });

  _liveTest('idle devices only send the fallback sync every two minutes', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    final runsA = _runs(a);
    final runsB = _runs(b);
    final requests = l.network.requests;
    l.wait(const Duration(minutes: 10));
    expect(runsA.count, inInclusiveRange(4, 5));
    expect(runsB.count, inInclusiveRange(4, 5));
    // Each run reads the server's health and pulls; the event streams stay
    // open (heartbeats need no requests).
    expect(l.network.requests - requests, lessThanOrEqualTo(2 * 5 * 2));
    expect(a.s.sync.liveConnections, 1);
    expect(b.s.sync.liveConnections, 1);
  });

  _liveTest('devices reconnect after the server restarts', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    l.server.restart();
    l.async.flushMicrotasks();
    expect(a.s.sync.live, isFalse);
    l.until(() => a.s.sync.live && b.s.sync.live, limit: const Duration(seconds: 3));
    expect(a.s.sync.liveConnections, 2);
    expect(b.s.sync.liveConnections, 2);
    expect(l.server.events.streams, 2);

    final folder = a.s.folders.create(name: 'After restart', color: 1);
    final took = l.until(() => b.s.folders.get(folder.id) != null);
    expect(took, lessThanOrEqualTo(const Duration(seconds: 5)));
  });

  _liveTest('a server down backs off: no storm of connections or syncs', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    final runsA = _runs(a);
    l.server
      ..down = true
      ..restart();
    final folder = a.s.folders.create(name: 'Offline', color: 1);
    l.wait(const Duration(minutes: 10));
    // Reconnecting: 1, 2, 4, … s, then once a minute.
    expect(a.s.sync.liveConnections, inInclusiveRange(10, 18));
    // Syncing: the fallback timer (every 45 s while the stream is down)
    // and retries of the write, backing off up to 2 minutes.
    expect(runsA.count, lessThanOrEqualTo(10 * 60 ~/ 45 + 8));
    expect(a.s.sync.state, SyncState.error);

    l.server.down = false;
    // Within the reconnection delay (at most a minute and a fifth), the
    // write is pushed and B hears of it.
    l.until(() => b.s.folders.get(folder.id) != null, limit: const Duration(seconds: 80));
    expect(a.s.sync.state, SyncState.idle);
    expect(a.s.sync.live, isTrue);
  });

  _liveTest('a run that works ends the backoff of failed ones', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    l.server
      ..down = true
      ..restart();
    // Syncs failing in a row: the next is tried two minutes later.
    for (var i = 0; i < 6; i++) {
      for (final d in [a, b]) {
        l.sync(d);
        expect(d.s.sync.state, SyncState.error);
      }
    }
    // The server is back; a run that works (a tap on Sync now, the
    // fallback timer) says so.
    l.server.down = false;
    for (final d in [a, b]) {
      l.sync(d);
      expect(d.s.sync.state, SyncState.idle);
    }
    l.until(() => a.s.sync.live && b.s.sync.live, limit: const Duration(seconds: 20));

    // B pushes once writing pauses, A pulls on its event: no backoff left.
    final folder = b.s.folders.create(name: 'Back', color: 1);
    final took = l.until(() => a.s.folders.get(folder.id) != null);
    expect(took, lessThanOrEqualTo(const Duration(seconds: 5)));
  });

  _liveTest('the stream is closed in the background and opened on return', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    a.s.sync.foreground = false;
    l.async.flushMicrotasks();
    expect(a.s.sync.live, isFalse);
    expect(l.server.events.streams, 1);
    final runsA = _runs(a);
    final folder = b.s.folders.create(name: 'Elsewhere', color: 1);
    l.wait(const Duration(seconds: 30));
    // Not heard of in the background (the fallback timer still runs).
    expect(a.s.folders.get(folder.id), isNull);
    expect(runsA.count, 0);
    expect(a.s.sync.liveConnections, 1);

    a.s.sync.foreground = true;
    // The new connection's first event says the feed moved on: A pulls.
    final took = l.until(() => a.s.folders.get(folder.id) != null);
    expect(took, lessThanOrEqualTo(const Duration(seconds: 3)));
    expect(a.s.sync.liveConnections, 2);
  });

  _liveTest('a rejected token closes the stream until the settings change', (l) {
    final a = l.device('a');
    l.wait(const Duration(seconds: 3));
    a.s.sync.configure(url: 'http://sync.test', token: 'not-the-token-0123456789');
    l.wait(const Duration(seconds: 3));
    expect(a.s.sync.waitsForSettings, isTrue);
    expect(a.s.sync.live, isFalse);
    final connections = a.s.sync.liveConnections;
    l.wait(const Duration(minutes: 5));
    expect(a.s.sync.liveConnections, connections);
    expect(l.server.events.streams, 0);

    a.s.sync.configure(url: 'http://sync.test', token: RealServer.token);
    l.until(() => a.s.sync.live, limit: const Duration(seconds: 3));
  });
}
