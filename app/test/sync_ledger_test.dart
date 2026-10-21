import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';

import 'support/fault_devices.dart';
import 'support/faulty_network.dart';
import 'support/random_edits.dart';
import 'support/real_server.dart';
import 'support/sync_ledger.dart';

// The ledger the sync property tests check devices against
// (support/sync_ledger.dart) must not report what the protocol does on
// purpose as a loss.

void main() {
  // Seen in the live sync property test under load (seed 84): a device
  // deleted a notebook forever and, pulling an edit made elsewhere
  // meanwhile, brought back the deletion's rows (Revival: a text box at a
  // newer version, holding its old edit). The other device, never seeing
  // the copy, deleted the notebook forever knowing that edit: the deletion
  // rightly stays (docs/SYNC_PROTOCOL.md, "Deletion conflicts"), and nothing
  // written is lost.
  test('a copy brought back is no new edit: deleting it knowingly loses nothing', () async {
    final server = RealServer();
    final network = FaultyNetwork(server, math.Random(1))..rate = 0;
    final time = SharedTime();
    final a = await FaultDevice.start(network, time, 'a');
    final b = await FaultDevice.start(network, time, 'b');
    final ledger = SyncLedger();
    Future<void> step(FaultDevice d, Future<void> Function(AppServices s) f) async {
      time.now += 1000;
      final before = SyncLedger.snapshot(d.s);
      await f(d.s);
      ledger.record(before, d.s);
    }

    try {
      late String notebook, box;
      await step(a, (s) async {
        notebook = s.notebooks
            .create(
              title: 'n',
              kind: NotebookKind.paged,
              paper: PaperStyle.blank,
              coverColor: 0xFF000000,
            )
            .id;
        await RandomEdits(s, math.Random(1)).newTextChain();
        box = s.database.db.select('SELECT id FROM elements').single['id'] as String;
      });
      await a.sync();
      await b.sync();
      // b deletes it forever, offline.
      await step(b, (s) async => s.notebooks.trash(notebook));
      await step(b, (s) async => s.notebooks.delete(notebook));
      // a writes in it meanwhile.
      await step(a, (s) => RandomEdits(s, math.Random(2)).stroke());
      await a.sync();
      // b pulls the stroke: the notebook and its text box come back.
      await step(b, (s) async => await b.sync());
      expect(b.s.database.db.select('SELECT deleted FROM elements WHERE id = ?', [box]).single, {
        'deleted': 0,
      });
      // a, not having pulled that, deletes the notebook forever too.
      await step(a, (s) async => s.notebooks.trash(notebook));
      await step(a, (s) async => s.notebooks.delete(notebook));
      for (final d in [a, b, a]) {
        await d.sync();
      }
      for (final d in [a, b]) {
        expect(d.s.database.db.select('SELECT deleted FROM elements WHERE id = ?', [box]).single, {
          'deleted': 1,
        });
      }
      expect(ledger.losses(a.s, witnesses: [b.s]), isEmpty);
    } finally {
      a.dispose();
      b.dispose();
      server.dispose();
    }
  });
}
