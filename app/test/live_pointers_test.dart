import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/live_ink/pointer_relay.dart';
import 'package:len/features/editor/live_ink/remote_pointers_overlay.dart';
import 'package:len/ink/input/ink_events.dart';
import 'package:len/ink/remote_ink.dart';
import 'package:len/ink/remote_pointers.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/sync/live_link.dart';
import 'package:len/sync/live_messages.dart';
import 'package:len/sync/live_rooms.dart';
import 'package:len/sync/remote_changes.dart';

import 'document_editor_test.dart' show pumpEditor, closeEditor;
import 'split_view_test.dart' show pumpWorkspace;
import 'support/live_devices.dart';
import 'support/zoom_fixtures.dart' show zoomSession;

// Toward real-time collaboration: other devices' pointers (hover, laser)
// shown live, and the provisional ink of their strokes handed over to the
// records without a gap (a page reloading whole, a snapped highlight).

/// Rooms with nb joined and [others] in it, with no connection.
LiveRooms _rooms({List<String> others = const ['c2']}) {
  final rooms = LiveRooms(LiveLink(connect: () => throw UnimplementedError(), onMessage: (_) {}))
    ..join('nb');
  rooms.receive(
    LivePresence('nb', [for (final c in others) (connection: c, deviceId: 'd$c', name: 'Android')]),
  );
  return rooms;
}

void _say(LiveRooms rooms, Map<String, Object?> data, {String from = 'c2'}) =>
    rooms.receive(LiveEphemeral(room: 'nb', from: from, deviceId: 'd$from', data: data));

/// Starts a stroke `w` on p1 by c2.
void _inkOn(LiveRooms rooms) => _say(rooms, {
  'k': 'ink',
  's': 'w',
  'page': 'p1',
  'tool': 'highlighter',
  'color': 0x80FFEE00,
  'width': 12,
  'from': 0,
  'p': [10, 10, 0.5, 60, 12, 0.5, 120, 11, 0.5],
});

void main() {
  liveTest('a hovering pointer and a laser show on the other device, live', (l) {
    final a = l.device('a');
    final b = l.device('b');
    l.wait(const Duration(seconds: 3));
    final events = InkEvents();
    final laser = LaserTrail();
    var sent = 0;
    final relay = PointerRelay(
      events: events,
      laser: laser,
      surface: () => 'page-1',
      send: (data) {
        sent++;
        a.s.sync.rooms.send('nb', data);
      },
      presence: a.s.sync.rooms,
      anyoneThere: () => a.s.sync.rooms.othersIn('nb').isNotEmpty,
    );
    addTearDown(relay.dispose);
    a.s.sync.rooms.join('nb');
    l.wait(const Duration(milliseconds: 100));
    // Alone in the room: nothing hooked in, nothing sent.
    expect(events.hovered, isNull);
    laser.down(Offset.zero);
    laser.up();
    expect(sent, 0);

    b.s.sync.rooms.join('nb');
    final pointers = RemotePointers(b.s.sync.rooms, room: 'nb');
    addTearDown(pointers.dispose);
    l.wait(const Duration(milliseconds: 100));
    expect(events.hovered, isNotNull, reason: 'someone is there: hooked in');

    // A pen hovering over a second (a sample every 8 ms): about 25 messages.
    for (var i = 0; i < 125; i++) {
      events.hovered!(Offset(100.0 + i, 50));
      l.wait(const Duration(milliseconds: 8), step: const Duration(milliseconds: 8));
    }
    expect(sent, inInclusiveRange(20, 30));
    l.wait(const Duration(milliseconds: 100));
    final shown = pointers.pointers.single;
    expect(shown.surface, 'page-1');
    expect(shown.hover, const Offset(224, 50));
    expect(pointers.nameOf(shown.connection), isNotEmpty);

    // At rest: hidden after a while.
    l.wait(RemotePointers.silence + const Duration(milliseconds: 600));
    expect(pointers.pointers.where((p) => p.hover != null), isEmpty);

    // The laser: its dot and trail replay there, held while pressed (even
    // still for long), fading once lifted.
    events.hovered!(null); // Pressing (as the input tells).
    laser.down(const Offset(10, 10));
    for (var i = 1; i <= 20; i++) {
      laser.move(Offset(10.0 + i * 5, 10));
      l.wait(const Duration(milliseconds: 10), step: const Duration(milliseconds: 10));
    }
    l.wait(const Duration(milliseconds: 100));
    var remote = pointers.pointers.single.laser;
    expect(remote.pressed, isTrue);
    expect(remote.length, 21, reason: 'every trail point');
    expect(remote.head, const Offset(110, 10));
    expect(remote.config.color, laser.config.color);
    l.wait(RemotePointers.silence * 2);
    expect(pointers.pointers.single.laser.pressed, isTrue, reason: 'held: kept alive');
    laser.up();
    l.wait(const Duration(milliseconds: 100));
    remote = pointers.pointers.single.laser;
    expect(remote.pressed, isFalse);
    remote.tick(0);
    remote.tick(5000);
    pointers.tick(5000);
    expect(pointers.isEmpty, isTrue, reason: 'faded');

    // Leaving: the pointer goes at once; alone again, unhooked.
    events.hovered!(const Offset(5, 5));
    l.wait(const Duration(milliseconds: 100));
    expect(pointers.isEmpty, isFalse);
    a.s.sync.rooms.leave('nb');
    l.wait(const Duration(milliseconds: 100));
    expect(pointers.isEmpty, isTrue);
    expect(events.hovered, isNull);
  });

  test('a pointer moving to another page starts afresh there; "gone" hides it', () {
    final rooms = _rooms();
    final pointers = RemotePointers(rooms, room: 'nb');
    addTearDown(pointers.dispose);
    _say(rooms, {
      'k': 'pointer',
      'page': 'p1',
      'at': [5, 5],
      'laser': {
        'mode': 'trail',
        'color': 0xFF2BD957,
        'size': 6,
        'duration': 1000,
        'fade': 'stroke',
        'hold': 2000,
        'down': true,
        'p': [1, 1, 2, 2, 3, 3, 4, 4],
        'starts': [0, 2],
      },
    });
    final laser = pointers.pointers.single.laser;
    expect(laser.length, 4);
    expect([for (var i = 0; i < 4; i++) laser.startsAt(i)], [true, false, true, false]);
    expect(laser.config.color, 0xFF2BD957);
    _say(rooms, {
      'k': 'pointer',
      'page': 'p2',
      'at': [7, 7],
    });
    final p = pointers.pointers.single;
    expect((p.surface, p.hover, p.laser.length), ('p2', const Offset(7, 7), 0));
    _say(rooms, {'k': 'pointer', 'page': 'p2'});
    pointers.tick(0);
    expect(pointers.isEmpty, isTrue);
    // Malformed: ignored.
    _say(rooms, {'k': 'pointer', 'page': 3, 'at': 'x'});
    _say(rooms, {
      'k': 'pointer',
      'page': 'p1',
      'at': [double.nan, 1],
    });
    expect(pointers.pointers.every((p) => p.hover == null), isTrue);
  });

  test('pointers paint on the pages a view shows, labelled', () {
    final rooms = _rooms();
    final pointers = RemotePointers(rooms, room: 'nb');
    addTearDown(pointers.dispose);
    _say(rooms, {
      'k': 'pointer',
      'page': 'p1',
      'at': [5, 5],
    });
    final asked = <String>[];
    final painter = RemotePointersPainter(
      pointers: pointers,
      viewport: ViewportController(),
      frameOf: (id) {
        asked.add(id);
        return const Rect.fromLTWH(100, 0, 800, 1000);
      },
      plate: const Color(0xFFEEEEEE),
      label: const TextStyle(fontSize: 12),
      dot: const Color(0xFF000000),
      halo: const Color(0xFFFFFFFF),
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(800, 600));
    recorder.endRecording().dispose();
    expect(asked, ['p1']);
  });

  test('a snapped highlight\'s ink stays until every stroke it became arrived', () {
    final rooms = _rooms();
    final remote = RemoteInk(rooms, room: 'nb');
    addTearDown(remote.dispose);
    _inkOn(rooms);
    _say(rooms, {
      'k': 'ink',
      's': 'w',
      'end': true,
      'strokes': ['h1', 'h2'],
    });
    expect(remote.strokesOn('p1'), hasLength(1));
    remote.landed(RemoteChanges()..addItem('p1', 'h1'));
    expect(remote.strokesOn('p1'), hasLength(1), reason: 'h2 is still on its way');
    remote.landed(RemoteChanges()..addItem('p1', 'h2'));
    expect(remote.strokesOn('p1'), isEmpty);
  });

  test('ink waits for a page reloading whole to show its stroke', () {
    final rooms = _rooms();
    var loaded = false;
    final remote = RemoteInk(rooms, room: 'nb')..shows = (surface, id) => loaded;
    addTearDown(remote.dispose);
    _inkOn(rooms);
    _say(rooms, {
      'k': 'ink',
      's': 'w',
      'end': true,
      'strokes': ['st'],
    });
    final many = RemoteChanges();
    for (var i = 0; i <= RemoteChanges.maxItems; i++) {
      many.addItem('p1', 'x$i');
    }
    many.addItem('p1', 'st');
    expect(many.itemsOf('p1'), isNull, reason: 'the page reloads whole');
    remote.landed(many);
    expect(remote.strokesOn('p1'), hasLength(1), reason: 'not drawn yet: the reload is on');
    expect(remote.reloading, {'p1'});
    remote.recheck();
    expect(remote.strokesOn('p1'), hasLength(1));
    loaded = true;
    remote.recheck();
    expect(remote.strokesOn('p1'), isEmpty);
    expect(remote.reloading, isEmpty);
  });

  testWidgets('in the editor: a surface reloading whole hands remote ink over without a gap', (
    tester,
  ) async {
    // A canvas: its reads answer a few frames later, as the background
    // reader's do.
    final (s, nb, _) = await pumpWorkspace(
      tester,
      kind: NotebookKind.canvas,
      reader: _SlowReader.new,
    );
    final session = zoomSession(tester);
    final model = session.canvas!;
    final surface = model.surfaceId;
    s.sync.rooms.receive(
      LivePresence(nb.id, const [(connection: 'c9', deviceId: 'd9', name: 'Android')]),
    );
    final points = [for (var i = 0; i < 20; i++) StrokePoint(100.0 + i * 5, 200.0 + i, 0.5)];
    LiveEphemeral say(Map<String, Object?> data) =>
        LiveEphemeral(room: nb.id, from: 'c9', deviceId: 'd9', data: data);
    s.sync.rooms
      ..receive(
        say({
          'k': 'ink',
          's': 'w1',
          'page': surface,
          'tool': 'ballpoint',
          'color': 0xFF0000FF,
          'width': 3,
          'from': 0,
          'p': [
            for (final p in points) ...[p.x, p.y, p.pressure],
          ],
        }),
      )
      ..receive(
        say({
          'k': 'ink',
          's': 'w1',
          'end': true,
          'strokes': ['st1'],
        }),
      );
    await tester.pump();
    final remote = session.shared.remoteInk;
    expect(remote.strokesOn(surface), hasLength(1));

    // Its record comes with many others: the canvas reloads whole.
    s.strokes.save([
      Stroke(
        id: 'st1',
        surfaceId: surface,
        tool: InkTool.ballpoint,
        color: 0xFF0000FF,
        width: 3,
        points: points,
        createdAt: 1,
      ),
    ]);
    final changes = RemoteChanges()..addItem(surface, 'st1');
    for (var i = 0; i < RemoteChanges.maxItems; i++) {
      changes.addItem(surface, 'gone-$i');
    }
    s.sync.debugAnnounce(changes);
    bool drawn() => model.strokeById('st1') != null;
    var frames = 0;
    for (; frames < 20 && (remote.strokesOn(surface).isNotEmpty || !drawn()); frames++) {
      expect(remote.strokesOn(surface).isNotEmpty || drawn(), isTrue, reason: 'never neither');
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(frames, greaterThan(1), reason: 'the reload took a while');
    expect(drawn(), isTrue);
    expect(remote.strokesOn(surface), isEmpty, reason: 'gone once its stroke is drawn');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('in the editor: another device\'s pointer shows over its page', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final page = s.pages.pagesOf(nb.id).first;
    final session = zoomSession(tester);
    s.sync.rooms
      ..receive(LivePresence(nb.id, const [(connection: 'c9', deviceId: 'd9', name: 'Linux')]))
      ..receive(
        LiveEphemeral(
          room: nb.id,
          from: 'c9',
          deviceId: 'd9',
          data: {
            'k': 'pointer',
            'page': page.id,
            'at': [120, 80],
          },
        ),
      );
    await tester.pump();
    expect(find.byType(RemotePointersOverlay), findsOneWidget);
    expect(session.shared.remotePointers.pointers.single.hover, const Offset(120, 80));
    expect(session.pointerRelay, isNotNull);
    expect(session.input.events.hovered, isNotNull, reason: 'someone is there: hooked in');
    s.sync.rooms.receive(LivePresence(nb.id, const []));
    await tester.pump();
    expect(session.shared.remotePointers.isEmpty, isTrue);
    expect(session.input.events.hovered, isNull);
    await closeEditor(tester);
  });
}

/// Answers reads 30 ms later (as a background isolate does).
class _SlowReader implements StrokeReader {
  _SlowReader(this.inner);

  final StrokeReader inner;

  Future<T> _later<T>(FutureOr<T> Function() answer) =>
      Future<void>.delayed(const Duration(milliseconds: 30)).then((_) => answer());

  @override
  Future<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) =>
      _later(() => inner.read(surfaceId, range, skip: skip));

  @override
  Future<Map<ChunkKey, ChunkDigest>> chunkDigests(String surfaceId, ChunkRange range) =>
      _later(() => inner.chunkDigests(surfaceId, range));

  @override
  Future<Map<ChunkKey, int>> chunkDensity(String surfaceId) =>
      _later(() => inner.chunkDensity(surfaceId));

  @override
  Future<Rect?> contentBounds(String surfaceId) => _later(() => inner.contentBounds(surfaceId));
}
