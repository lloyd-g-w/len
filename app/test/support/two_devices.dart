import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/syncable.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:sqlite3/common.dart';

import 'fake_server.dart';
import 'test_database.dart';

/// Wall-clock time shared by the devices of a test.
class TestTime {
  int now = 1000;
  void tick([int ms = 10]) => now += ms;
}

/// A deterministic clock: ids are the prefix followed by 0, 1, …
class DeviceClock extends Clock {
  DeviceClock(this.time, this.prefix);

  final TestTime time;
  final String prefix;
  int _ids = 0;

  @override
  int nowMs() => time.now;

  @override
  String newId() => '$prefix${_ids++}';
}

/// An app installation with its own in-memory database, syncing with
/// [server].
class TestDevice {
  TestDevice(this.server, this.time, String prefix) : clock = DeviceClock(time, prefix) {
    s = AppServices.create(openTestDatabase(), clock: clock);
    addTearDown(s.dispose);
  }

  final FakeServer server;
  final TestTime time;
  final DeviceClock clock;
  late final AppServices s;

  Future<RemoteChanges> sync() {
    time.tick();
    return s.sync.engine.sync(apiFor(server));
  }

  CommonDatabase get db => s.database.db;

  /// Every row with unpushed changes, in any synced table.
  List<SyncRecord> get dirty => [
    for (final store in s.sync.engine.stores) ...store.dirtyRecords(1000),
  ];
}

/// Two devices ('a…' and 'b…') on one fresh server.
(TestDevice, TestDevice) twoDevices() {
  final time = TestTime();
  final server = FakeServer();
  return (TestDevice(server, time, 'a'), TestDevice(server, time, 'b'));
}

/// Syncs [from] and then [to], so [to] sees everything [from] did.
Future<void> send(TestDevice from, TestDevice to) async {
  await from.sync();
  await to.sync();
}
