import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/sync/sync_controller.dart';
import 'package:sqlite3/common.dart' show Row;

import 'faulty_network.dart';

/// Wall-clock time shared by the devices of a run.
class SharedTime {
  int now = 1760000000000;
}

/// A device's clock: [skew] ms off the shared time (it may jump), ids the
/// prefix followed by 0, 1, … (kept across app runs).
class SkewedClock extends Clock {
  SkewedClock(this.time, this.prefix, this.skew);

  final SharedTime time;
  final String prefix;
  int skew;
  int _ids = 0;

  @override
  int nowMs() => time.now + skew;

  @override
  String newId() => '$prefix${_ids++}';
}

/// An app installation on its own database file, syncing through a
/// [FaultyNetwork]. It can be killed (its database closed in the middle of
/// whatever it does) and started again on the same files.
class FaultDevice {
  FaultDevice._(this.network, SharedTime time, this.prefix, {int skew = 0})
    : clock = SkewedClock(time, prefix, skew),
      _dir = Directory.systemTemp.createTempSync('len-fault-$prefix-') {
    _start();
  }

  /// A device set up to sync (its settings saved).
  static Future<FaultDevice> start(
    FaultyNetwork network,
    SharedTime time,
    String prefix, {
    int skew = 0,
  }) async {
    final device = FaultDevice._(network, time, prefix, skew: skew);
    device.s.sync.configure(url: 'http://sync.test', token: _token);
    await device.s.sync.tokens.save(_token);
    return device;
  }

  static const _token = 'real-server-token-0123456789';

  final FaultyNetwork network;
  final String prefix;
  final SkewedClock clock;
  final Directory _dir;

  /// The device's files (blobs), which outlive app runs.
  final MemoryBlobBackend files = MemoryBlobBackend();

  late AppServices s;

  /// Whether the app runs (false once killed, until [restart]).
  bool alive = false;

  /// App runs so far.
  int runs = 0;

  /// Syncs that ended (or were killed) while still "syncing".
  final List<String> stuck = [];

  void _start() {
    final run = ++runs;
    bool gone() => !alive || run != runs;
    s = AppServices.create(
      AppDatabase.open('${_dir.path}/len.db'),
      clock: clock,
      blobBackend: files,
      syncApiFactory: (url, token) => SyncApi(
        baseUrl: url,
        token: token,
        client: network.clientFor(onKill: kill, killed: gone),
      ),
    );
    alive = true;
  }

  /// Kills the app: its database closes under whatever runs.
  void kill() {
    if (!alive) return;
    alive = false;
    s.dispose();
  }

  /// Starts the app again (killing it first if it runs).
  void restart() {
    kill();
    _start();
  }

  /// The app running (started again if it was killed).
  AppServices get app {
    if (!alive) _start();
    return s;
  }

  /// Runs one sync through the controller, as the app does; [killAfter]
  /// kills the app that long after the sync began, wherever it is then.
  /// Never throws for a failed sync; fails the test if the sync hangs or
  /// leaves the controller "syncing".
  Future<void> sync({Duration? killAfter}) async {
    final services = app;
    final killer = killAfter == null ? null : Timer(killAfter, kill);
    try {
      await services.sync.syncNow().timeout(const Duration(seconds: 60));
    } on TimeoutException {
      fail('$prefix: sync hung');
    } finally {
      killer?.cancel();
    }
    if (alive && identical(services, s) && services.sync.state == SyncState.syncing) {
      stuck.add('$prefix run $runs');
    }
  }

  void dispose() {
    kill();
    _dir.deleteSync(recursive: true);
  }
}

/// The synced tables, parents first.
const syncedTables = [
  'folders',
  'templates',
  'notebook_styles',
  'notebooks',
  'pages',
  'outline',
  'recordings',
  'strokes',
  'elements',
  'recognised_text',
];

/// Every synced row (and the chunk indexes), comparable across devices:
/// without local bookkeeping, and tombstones only by version and base (a device keeps
/// the payload of rows it saw live, by design).
Map<String, Object?> syncedState(AppServices s) => {
  for (final table in syncedTables)
    table: {
      for (final row in s.database.db.select('SELECT * FROM $table ORDER BY id'))
        row['id'] as String: row['deleted'] == 1
            ? '${row['updated_at']}/${row['device_id']}/deleted${_baseOf(row)}'
            : {
                for (final e in row.entries)
                  if (!_bookkeeping.contains(e.key))
                    e.key: e.value is List<int> ? base64Encode(e.value as List<int>) : e.value,
                if (row['origin_for'] == row['updated_at'])
                  'origin': '${row['origin_at']}/${row['origin_device']}',
              },
    },
  for (final (table, column) in [('stroke_chunks', 'stroke_id'), ('element_chunks', 'element_id')])
    table: [
      for (final r in s.database.db.select(
        'SELECT * FROM $table ORDER BY surface_id, cx, cy, $column',
      ))
        '${r['surface_id']}:${r['cx']},${r['cy']}:${r[column]}',
    ],
};

/// Local columns that are no synced state as such: unpushed changes, and
/// the origin and base of rows edited in place (`EditOrigins`; synced as a
/// record's `base`, compared as such).
const _bookkeeping = {
  'dirty',
  'base_at',
  'base_device',
  'origin_at',
  'origin_device',
  'origin_for',
};

/// The `base` a tombstone carries, as text ('' for none).
String _baseOf(Row row) =>
    row['base_at'] == null ? '' : ' base ${row['base_at']}/${row['base_device']}';
