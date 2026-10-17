@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ink/remote_ink.dart';
import 'package:len/ink/render/remote_ink_painter.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/sync/live_link.dart';
import 'package:len/sync/live_rooms.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:len/ui/app_theme.dart';

import 'support/big_library.dart';
import 'support/frame_counts.dart';

/// Writing with other devices in the notebook (live sync's rooms): what
/// the local pen pays while three others write, point and come and go.
///
/// - a live push of a just-written stroke (the 150 ms throttle's tick:
///   dirty rows read, encoded as the connection sends them, marked clean);
/// - painting the strokes three other devices are writing (remote ink), by
///   how long they are;
/// - frames of the editor (widgets rebuilt, render objects painted) with
///   three remote writers, the local pen writing alone and with them,
///   three remote pointers moving, and presence changing.
///
/// Run: `tool/heavy.sh flutter test test/perf/live_collab_perf_test.dart`.
void main() {
  test('live push: one stroke per tick in a notebook of 5,700 strokes', () async {
    final clock = BenchClock();
    final services = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(services.dispose);
    final nb = _notebook(services);
    for (final page in services.pages.pagesOf(nb.id)) {
      services.strokes.save(pageOfInk(page.id, clock, lines: 25, seed: page.hashCode));
    }
    final engine = services.sync.engine;
    var bytes = 0;
    Future<LivePushed> send(List<SyncRecord> records, {required int since, required bool current}) {
      final text =
          '{"type":"push","id":1,"since":$since,"current":$current,"records":'
          '[${records.map((r) => jsonEncode(r.toJson())).join(',')}]}';
      bytes = text.length;
      return Future.value(LivePushed(id: 1, applied: records.length, serverSeq: 1));
    }

    await engine.pushLive(send); // Everything written so far.
    final page = services.pages.pagesOf(nb.id).first.id;
    var best = 1 << 30;
    for (var i = 0; i < 40; i++) {
      services.strokes.save([_stroke(page, clock, 'tick-$i', points: 600)]);
      final watch = Stopwatch()..start();
      await engine.pushLive(send);
      if (watch.elapsedMicroseconds < best) best = watch.elapsedMicroseconds;
    }
    report('LIVE push tick (a 600-point stroke): $best µs best of 40, $bytes bytes');
  });

  test('remote ink: painting three strokes being written, by length', () {
    final link = LiveLink(connect: () => throw UnimplementedError(), onMessage: (_) {});
    final rooms = LiveRooms(link)..join('nb');
    rooms.receive(LivePresence('nb', _members(3)));
    final remote = RemoteInk(rooms, room: 'nb');
    final viewport = ViewportController();
    final painter = RemoteInkPainter(
      remote: remote,
      viewport: viewport,
      frameOf: (_) => const Rect.fromLTWH(0, 0, 800, 1100),
    );
    final writers = [for (var d = 0; d < 3; d++) _Writer('nb', d, 'p1')];
    final line = StringBuffer('LIVE remote ink paint (a message, then a paint):');
    var sent = 0;
    for (final length in [120, 600, 2400]) {
      // Grow to [length], then time a message (12 new points) and a paint.
      var best = 1 << 30;
      for (var round = 0; round < 12; round++) {
        while (sent < length) {
          for (final w in writers) {
            rooms.receive(w.next(12));
          }
          sent += 12;
        }
        final watch = Stopwatch()..start();
        for (final w in writers) {
          rooms.receive(w.next(12));
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), const Size(1000, 1300));
          recorder.endRecording().dispose();
        }
        sent += 12;
        if (watch.elapsedMicroseconds < best) best = watch.elapsedMicroseconds;
      }
      line.write(' $length points: ${(best / 3).toStringAsFixed(0)} µs;');
    }
    report(line.toString());
    remote.dispose();
    rooms.dispose();
  });

  testWidgets('editor frames with three other devices in the notebook', (tester) async {
    final services = await _pumpEditor(tester);
    final nb = services.notebooks.list().single;
    final pages = services.pages.pagesOf(nb.id);
    final rooms = services.sync.rooms;
    rooms.receive(LivePresence(nb.id, _members(3)));
    await tester.pumpAndSettle();
    final writers = [for (var d = 0; d < 3; d++) _Writer(nb.id, d, pages.first.id)];

    /// Each writer sends 12 points every third frame (50 ms at 240 Hz),
    /// one writer a frame.
    void remoteInk(int i) => rooms.receive(writers[i % 3].next(12));

    report(
      'LIVE remote ink, 3 writers:   ${await countFrames((i) async {
        remoteInk(i);
        await tester.pump(const Duration(milliseconds: 16));
      }, 120)}',
    );
    for (final w in writers) {
      rooms.receive(w.end());
    }
    await tester.pump(const Duration(seconds: 1));

    for (final withRemote in [false, true]) {
      final pen = await tester.startGesture(const Offset(300, 700), kind: PointerDeviceKind.stylus);
      final run = await countFrames((i) async {
        await pen.moveTo(Offset(300 + (i % 100) * 4.0, 700 + (i ~/ 100) * 30.0 + (i % 7) * 3));
        if (withRemote && i.isEven) remoteInk(i ~/ 2);
        await tester.pump(const Duration(milliseconds: 8));
      }, 200);
      await pen.up();
      report('LIVE local pen${withRemote ? ' + 3 writers' : ', alone    '}: $run');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }
    for (final w in writers) {
      rooms.receive(w.end());
    }
    await tester.pump(const Duration(seconds: 1));

    report(
      'LIVE remote pointers, 3:       ${await countFrames((i) async {
        final d = i % 3;
        rooms.receive(_say(nb.id, d, {
          'k': 'pointer',
          'page': pages.first.id,
          'at': [100.0 + d * 200 + (i % 50) * 3, 300.0 + (i % 40) * 2],
        }));
        await tester.pump(const Duration(milliseconds: 16));
      }, 120)}',
    );
    report(
      'LIVE presence, join/leave:     ${await countFrames((i) async {
        rooms.receive(LivePresence(nb.id, _members(i.isEven ? 2 : 3)));
        await tester.pump(const Duration(milliseconds: 16));
      }, 60)}',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    services.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// [n] other devices in a room.
List<RoomMember> _members(int n) => [
  for (var d = 0; d < n; d++) (connection: 'c$d', deviceId: 'd$d', name: 'Tablet $d'),
];

LiveEphemeral _say(String room, int device, Map<String, Object?> data) =>
    LiveEphemeral(room: room, from: 'c$device', deviceId: 'd$device', data: data);

/// Another device writing a line of handwriting on [page], 600 points a
/// stroke, as its live ink relay sends it.
class _Writer {
  _Writer(this.room, this.device, this.page);

  final String room;
  final int device;
  final String page;
  int _stroke = 0;
  int _sent = 0;

  LiveEphemeral next(int count) {
    final points = [
      for (var i = _sent; i < _sent + count; i++) ...[
        (60 + (i % 600) * 1.1).toDouble(),
        100.0 + device * 250 + (_stroke % 4) * 40 + 8 * _wave(i),
        0.5,
      ],
    ];
    final message = _say(room, device, {
      'k': 'ink',
      's': 'w$device-$_stroke',
      'page': page,
      'tool': 'ballpoint',
      'color': 0xFF1565C0,
      'width': 2,
      'style': StrokeStyle.defaultsFor(InkTool.ballpoint).toJson(),
      'from': _sent,
      'p': points,
    });
    _sent += count;
    return message;
  }

  LiveEphemeral end() {
    final message = _say(room, device, {'k': 'ink', 's': 'w$device-$_stroke', 'end': true});
    _stroke++;
    _sent = 0;
    return message;
  }

  static double _wave(int i) => ((i * 7) % 23 - 11) / 11;
}

Notebook _notebook(AppServices services) {
  final nb = services.notebooks.create(
    title: 'Together',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  for (var i = 0; i < 2; i++) {
    services.pages.addPage(
      nb.id,
      template: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
    );
  }
  return nb;
}

Stroke _stroke(String surface, BenchClock clock, String id, {required int points}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: [for (var p = 0; p < points; p++) StrokePoint(10.0 + p * 0.8, 20.0 + (p % 9), 0.5)],
  createdAt: clock.nowMs(),
);

/// Three ruled pages of handwriting in a tablet-sized editor, as the
/// paged scroll benchmark opens them.
Future<AppServices> _pumpEditor(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1000, 1300)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = BenchClock();
  final services = AppServices.create(AppDatabase.inMemory(), clock: clock);
  final nb = _notebook(services);
  for (final (i, page) in services.pages.pagesOf(nb.id).indexed) {
    services.strokes.save(pageOfInk(page.id, clock, lines: 25, seed: i));
  }
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}
