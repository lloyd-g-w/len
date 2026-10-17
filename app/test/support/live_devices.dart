import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/sync/sync_controller.dart';

import 'fault_devices.dart';
import 'faulty_network.dart';
import 'real_server.dart';

/// Devices on one real server, on fake time.
class LiveDevices {
  LiveDevices(this.async) : server = RealServer() {
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
  void wait(Duration duration, {Duration step = const Duration(milliseconds: 100)}) {
    for (var t = Duration.zero; t < duration; t += step) {
      time.now += step.inMilliseconds;
      async.elapse(step);
    }
  }

  /// Waits until [done] holds (at most [limit]) and returns how long it took.
  Duration until(
    bool Function() done, {
    Duration limit = const Duration(minutes: 5),
    Duration step = const Duration(milliseconds: 100),
  }) {
    var waited = Duration.zero;
    while (!done()) {
      if (waited >= limit) fail('not within $limit');
      wait(step, step: step);
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
Runs runs(FaultDevice device) => Runs(device.s.sync);

class Runs {
  Runs(this.sync) : _was = sync.state {
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

/// A test of [LiveDevices] on fake time.
void liveTest(String name, void Function(LiveDevices live) body) {
  test(name, () {
    fakeAsync((async) {
      final l = LiveDevices(async);
      try {
        body(l);
      } finally {
        l.dispose();
      }
    });
  });
}
