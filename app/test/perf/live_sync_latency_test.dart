@Tags(['perf'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/templates/paper_style.dart';
import 'package:len/sync/sync_controller.dart';
import 'package:len/sync/sync_engine.dart';

import '../support/socket_server.dart';

// How long an edit takes from one device to another over live sync: the
// real server on loopback, two devices as the app runs them (real HTTP and
// WebSocket). Prints the latencies of strokes (each a pen-up: saved,
// pushed a frame later) until the other device's database holds them:
// written a quarter of a second apart (handwriting), and back to back
// (each as soon as the one before arrived: within 150 ms of the last push,
// so it waits for the rest of those 150 ms).

void main() {
  test('stroke latency over the live connection', () async {
    final server = await SocketServer.start();
    final a = await server.device();
    final b = await server.device();
    addTearDown(() async {
      a.dispose();
      b.dispose();
      await server.close();
    });
    await waitFor(
      () =>
          a.sync.connected &&
          b.sync.connected &&
          a.sync.engine.liveReady(server.store.serverId) &&
          b.sync.engine.liveReady(server.store.serverId) &&
          a.sync.state != SyncState.syncing &&
          b.sync.state != SyncState.syncing,
    );
    final notebook = a.notebooks.create(
      title: 'Latency',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF000000,
    );
    final page = a.pages.pagesOf(notebook.id).first;
    await waitFor(() => b.pages.pagesOf(notebook.id).isNotEmpty);

    Future<List<int>> measure(int count, {required Duration apart}) async {
      final latencies = <int>[];
      for (var i = 0; i < count; i++) {
        await Future<void>.delayed(apart);
        final stroke = Stroke(
          id: a.clock.newId(),
          surfaceId: page.id,
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: [for (var p = 0; p < 120; p++) StrokePoint(10.0 + p, 20.0 + i * 5, 0.5)],
          createdAt: a.clock.nowMs(),
        );
        final watch = Stopwatch()..start();
        a.strokes.save([stroke]);
        await waitFor(
          () => b.database.db.select('SELECT 1 FROM strokes WHERE id = ?', [stroke.id]).isNotEmpty,
        );
        latencies.add(watch.elapsedMilliseconds);
      }
      return latencies..sort();
    }

    String summary(List<int> l) {
      int at(double q) => l[((l.length - 1) * q).round()];
      return 'median ${at(0.5)}, p90 ${at(0.9)}, min ${l.first}, max ${l.last}';
    }

    final apart = await measure(40, apart: const Duration(milliseconds: 250));
    final backToBack = await measure(40, apart: Duration.zero);
    // ignore: avoid_print
    print('live sync stroke latency (ms): 250 ms apart: ${summary(apart)}');
    // ignore: avoid_print
    print('live sync stroke latency (ms): back to back: ${summary(backToBack)}');
    expect(apart[apart.length ~/ 2], lessThan(1000), reason: 'generous: a busy machine');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
