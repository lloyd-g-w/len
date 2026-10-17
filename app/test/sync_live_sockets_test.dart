import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/templates/paper_style.dart';
import 'package:len/ink/remote_ink.dart';
import 'package:len/sync/sync_controller.dart';
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
    // Connected, and the runs the app started with over, with nothing
    // left for another (a run carries the edits made while it runs, which
    // then never go over the connection: a busy machine's runs are slow).
    bool settled(AppServices s) =>
        s.sync.connected &&
        s.sync.engine.liveReady(server.store.serverId) &&
        s.sync.state == SyncState.idle &&
        s.sync.engine.knownSeq == server.store.currentSeq() &&
        !s.sync.engine.hasDirtyRows();
    await waitFor(() => settled(a) && settled(b));
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
    // The notebook, the stroke, its deletion. (A push counts once its
    // answer is back, which may be after the other device applied it.)
    await waitFor(() => a.sync.livePushes >= 3 && b.sync.liveApplied >= 3);
    expect(server.live.connections, 2);
  });

  test('rooms: presence and live ink travel between the devices', () async {
    a.sync.rooms.join('nb');
    b.sync.rooms.join('nb');
    await waitFor(
      () => a.sync.rooms.othersIn('nb').isNotEmpty && b.sync.rooms.othersIn('nb').isNotEmpty,
    );
    expect(b.sync.rooms.othersIn('nb').single.deviceId, a.settings.deviceId());
    final remote = RemoteInk(b.sync.rooms, room: 'nb');
    addTearDown(remote.dispose);
    a.sync.rooms.send('nb', {
      'k': 'ink',
      's': 'x',
      'page': 'p1',
      'tool': 'ballpoint',
      'color': 0xFF000000,
      'width': 2,
      'from': 0,
      'p': [0, 0, 0.5, 10, 10, 0.5],
    });
    await waitFor(() => remote.strokesOn('p1').isNotEmpty);
    // The writer closes the notebook: its ink goes with it.
    a.sync.rooms.leave('nb');
    await waitFor(() => remote.strokesOn('p1').isEmpty && b.sync.rooms.othersIn('nb').isEmpty);
  });
}
