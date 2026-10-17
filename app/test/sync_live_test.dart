import 'package:flutter_test/flutter_test.dart';
import 'package:len/sync/sync_controller.dart';

import 'support/live_devices.dart';
import 'support/real_server.dart';

// Live sync against the real server (`server/`) in this process, on fake
// time: a write goes over the live connection (`/v1/live`) a moment after
// it is committed and reaches the other devices at once; where live
// connections fail, the event stream (`/v1/events`) makes them pull within
// seconds; and nothing runs more than it needs to.

void main() {
  const ms10 = Duration(milliseconds: 10);

  liveTest('an edit reaches another device a moment after it is committed', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    expect(a.s.sync.connected, isTrue);
    expect(b.s.sync.connected, isTrue);
    expect(l.server.live.connections, 2);
    expect(l.server.events.streams, 0, reason: 'no event stream while live connections work');
    final runsA = runs(a);
    final runsB = runs(b);
    final requests = l.network.requests;

    final folder = a.s.folders.create(name: 'Live', color: 1);
    final took = l.until(() => b.s.folders.get(folder.id) != null, step: ms10);
    // The push goes a frame after the write; the rest is in memory.
    expect(took, lessThanOrEqualTo(const Duration(milliseconds: 50)));
    expect(a.s.sync.livePushes, 1);
    expect(b.s.sync.liveApplied, 1);
    // No run and no HTTP request for it; the fallback timer waits.
    l.wait(const Duration(seconds: 100));
    expect(runsA.count, 0);
    expect(runsB.count, 0);
    expect(l.network.requests, requests);
    expect(a.s.sync.engine.hasDirtyRows(), isFalse);
    // The feed position moved on with the records: nothing to pull.
    expect(b.s.sync.settings.syncLastSeq, l.server.store.currentSeq());
  });

  liveTest('writing goes out at once, bursts coalesced', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    final runsA = runs(a);
    String? last;
    // Slow writing: every write its own push.
    for (var i = 0; i < 20; i++) {
      last = a.s.folders.create(name: 'Slow $i', color: 1).id;
      l.wait(const Duration(milliseconds: 400), step: ms10);
      expect(b.s.folders.get(last), isNotNull);
    }
    expect(a.s.sync.livePushes, 20);
    // Fast writing (every 20 ms for 10 s): a push every 150 ms or so.
    for (var i = 0; i < 500; i++) {
      last = a.s.folders.create(name: 'Fast $i', color: 1).id;
      l.wait(const Duration(milliseconds: 20), step: ms10);
    }
    expect(a.s.sync.livePushes - 20, inInclusiveRange(55, 75));
    l.until(() => b.s.folders.get(last!) != null, limit: const Duration(seconds: 1), step: ms10);
    expect(b.s.folders.list().length, 520);
    expect(runsA.count, 0);
  });

  liveTest('idle devices only send the fallback sync every two minutes', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    final runsA = runs(a);
    final runsB = runs(b);
    final requests = l.network.requests;
    l.wait(const Duration(minutes: 10));
    expect(runsA.count, inInclusiveRange(4, 5));
    expect(runsB.count, inInclusiveRange(4, 5));
    // Each run reads the server's health and pulls; the live connections
    // stay open (heartbeats need no requests).
    expect(l.network.requests - requests, lessThanOrEqualTo(2 * 5 * 2));
    expect(a.s.sync.socketConnections, 1);
    expect(b.s.sync.socketConnections, 1);
    expect(a.s.sync.liveConnections, 0);
  });

  liveTest('devices reconnect after the server restarts', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    l.server.restart();
    l.async.flushMicrotasks();
    expect(a.s.sync.live, isFalse);
    l.until(() => a.s.sync.connected && b.s.sync.connected, limit: const Duration(seconds: 3));
    expect(a.s.sync.socketConnections, 2);
    expect(b.s.sync.socketConnections, 2);
    expect(l.server.live.connections, 2);

    final folder = a.s.folders.create(name: 'After restart', color: 1);
    final took = l.until(() => b.s.folders.get(folder.id) != null, step: ms10);
    expect(took, lessThanOrEqualTo(const Duration(milliseconds: 50)));
  });

  liveTest('what was written while the connection was down follows when it is back', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    l.server.liveDown = true;
    l.network.cutLive();
    l.async.flushMicrotasks();
    // Written while disconnected: the run after writing pauses pushes it,
    // and B (without a live connection either) pulls on the event stream.
    final early = a.s.folders.create(name: 'While down', color: 1);
    final took = l.until(() => b.s.folders.get(early.id) != null);
    expect(took, lessThanOrEqualTo(const Duration(seconds: 8)));
    expect(b.s.sync.connected, isFalse);
    expect(l.server.events.streams, 2, reason: 'the event stream is the fallback');

    l.server.liveDown = false;
    l.until(() => a.s.sync.connected && b.s.sync.connected, limit: const Duration(seconds: 80));
    l.until(() => l.server.events.streams == 0, limit: const Duration(seconds: 1));
    final late = b.s.folders.create(name: 'Back', color: 1);
    l.until(() => a.s.folders.get(late.id) != null, limit: const Duration(milliseconds: 300));
  });

  liveTest('records a device missed are pulled: a gap is never skipped', (l) {
    final a = l.device('a');
    final b = l.device('b');
    final c = l.device('c');
    l.wait(const Duration(seconds: 3));
    // B's connection drops; C writes meanwhile; B's next connection says
    // the feed moved on, and B pulls, and applies live again after.
    l.server.liveDown = true;
    l.network.cutLive();
    final missed = c.s.folders.create(name: 'Missed', color: 1);
    l.wait(const Duration(seconds: 6));
    expect(b.s.folders.get(missed.id), isNotNull, reason: 'pulled on the event stream');
    l.server.liveDown = false;
    l.until(() => a.s.sync.connected && b.s.sync.connected && c.s.sync.connected);
    final next = a.s.folders.create(name: 'Next', color: 1);
    l.until(() => b.s.folders.get(next.id) != null, limit: const Duration(milliseconds: 300));
    expect(b.s.sync.settings.syncLastSeq, l.server.store.currentSeq());
  });

  liveTest('a server down backs off: no storm of connections or syncs', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    final runsA = runs(a);
    l.server
      ..down = true
      ..restart();
    final folder = a.s.folders.create(name: 'Offline', color: 1);
    l.wait(const Duration(minutes: 10));
    // Reconnecting: 1, 2, 4, … s, then once a minute (live connections and
    // event streams alike).
    expect(a.s.sync.socketConnections, inInclusiveRange(10, 18));
    expect(a.s.sync.liveConnections, inInclusiveRange(8, 18));
    // Syncing: the fallback timer (every 45 s while disconnected) and
    // retries of the write, backing off up to 2 minutes.
    expect(runsA.count, lessThanOrEqualTo(10 * 60 ~/ 45 + 8));
    expect(a.s.sync.state, SyncState.error);

    l.server.down = false;
    // Within the reconnection delay (at most a minute and a fifth), the
    // write is pushed and B hears of it.
    l.until(() => b.s.folders.get(folder.id) != null, limit: const Duration(seconds: 80));
    l.until(() => a.s.sync.state == SyncState.idle, limit: const Duration(seconds: 10));
    l.until(() => a.s.sync.connected, limit: const Duration(seconds: 80));
  });

  liveTest('a run that works ends the backoff of failed ones', (l) {
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
    l.until(() => a.s.sync.connected && b.s.sync.connected, limit: const Duration(seconds: 80));

    final folder = b.s.folders.create(name: 'Back', color: 1);
    final took = l.until(() => a.s.folders.get(folder.id) != null, step: ms10);
    expect(took, lessThanOrEqualTo(const Duration(milliseconds: 300)));
  });

  liveTest('the connection is closed in the background and opened on return', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    a.s.sync.foreground = false;
    l.async.flushMicrotasks();
    expect(a.s.sync.live, isFalse);
    expect(l.server.live.connections, 1);
    final runsA = runs(a);
    final folder = b.s.folders.create(name: 'Elsewhere', color: 1);
    l.wait(const Duration(seconds: 30));
    // Not heard of in the background (the fallback timer still runs).
    expect(a.s.folders.get(folder.id), isNull);
    expect(runsA.count, 0);
    expect(a.s.sync.socketConnections, 1);

    a.s.sync.foreground = true;
    // The new connection's greeting says the feed moved on: A pulls.
    final took = l.until(() => a.s.folders.get(folder.id) != null);
    expect(took, lessThanOrEqualTo(const Duration(seconds: 3)));
    expect(a.s.sync.socketConnections, 2);
  });

  liveTest('a rejected token closes the connection until the settings change', (l) {
    final a = l.device('a');
    l.wait(const Duration(seconds: 3));
    a.s.sync.configure(url: 'http://sync.test', token: 'not-the-token-0123456789');
    l.wait(const Duration(seconds: 3));
    expect(a.s.sync.waitsForSettings, isTrue);
    expect(a.s.sync.live, isFalse);
    final connections = a.s.sync.socketConnections;
    l.wait(const Duration(minutes: 5));
    expect(a.s.sync.socketConnections, connections);
    expect(l.server.live.connections, 0);
    expect(l.server.events.streams, 0);

    a.s.sync.configure(url: 'http://sync.test', token: RealServer.token);
    l.until(() => a.s.sync.connected, limit: const Duration(seconds: 3));
  });
}
