import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/templates/paper_style.dart';
import 'package:len/sync/sync_engine.dart';

import 'support/socket_server.dart';

// Live sync as the app runs it, over real sockets: two devices and the
// real server on loopback (HTTP for runs, a WebSocket for `/v1/live`).
// test/perf/live_sync_latency_test.dart measures how long an edit takes.

Stroke _stroke(AppServices s, String surface) => Stroke(
  id: s.clock.newId(),
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: [for (var i = 0; i < 50; i++) StrokePoint(10.0 + i, 10.0 + i, 0.5)],
  createdAt: s.clock.nowMs(),
);

void main() {
  late SocketServer server;
  late AppServices a;
  late AppServices b;

  setUp(() async {
    server = await SocketServer.start();
    a = await server.device();
    b = await server.device();
    await waitFor(
      () =>
          a.sync.connected &&
          b.sync.connected &&
          a.sync.engine.liveReady(server.store.serverId) &&
          b.sync.engine.liveReady(server.store.serverId),
    );
  });

  tearDown(() async {
    a.dispose();
    b.dispose();
    await server.close();
  });

  test('a stroke, a deletion and a notebook travel over the live connection', () async {
    final notebook = a.notebooks.create(
      title: 'Shared',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF000000,
    );
    await waitFor(() => b.notebooks.get(notebook.id) != null);
    final page = a.pages.pagesOf(notebook.id).first;
    await waitFor(() => b.pages.pagesOf(notebook.id).isNotEmpty);

    final stroke = _stroke(a, page.id);
    final watch = Stopwatch()..start();
    a.strokes.save([stroke]);
    bool arrived() => b.database.db.select('SELECT 1 FROM strokes WHERE id = ? AND deleted = 0', [
      stroke.id,
    ]).isNotEmpty;
    await waitFor(arrived);
    final took = watch.elapsed;
    // ignore: avoid_print
    print('live sync over loopback: a stroke took ${took.inMilliseconds} ms');
    expect(took, lessThan(const Duration(seconds: 5)), reason: 'generous: a busy machine');

    a.strokes.delete([stroke.id]);
    await waitFor(() => !arrived());
    expect(a.sync.livePushes, greaterThanOrEqualTo(2)); // The stroke, its deletion.
    expect(b.sync.liveApplied, greaterThanOrEqualTo(2));
    expect(server.live.connections, 2);
  });
}
