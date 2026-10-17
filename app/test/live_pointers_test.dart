import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/live_ink/pointer_relay.dart';
import 'package:len/features/editor/live_ink/remote_pointers_overlay.dart';
import 'package:len/features/editor/zoom/zoom_box_paper.dart';
import 'package:len/ink/input/ink_events.dart';
import 'package:len/ink/remote_ink.dart';
import 'package:len/ink/remote_pointers.dart';
import 'package:len/ink/render/remote_ink_painter.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/sync/live_link.dart';
import 'package:len/sync/live_messages.dart';
import 'package:len/sync/live_rooms.dart';
import 'package:len/sync/remote_changes.dart';

import 'document_editor_test.dart' show pumpEditor, closeEditor;
import 'split_view_test.dart' show pumpWorkspace;
import 'support/live_devices.dart';
import 'support/zoom_fixtures.dart' show openZoom, zoomSession;

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
        'p': [1, 1, 0.5, 2, 2, 0.5, 3, 3, 0.5, 4, 4, 0.5],
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
      paperOf: (_) => PaperColor.white,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(800, 600));
    recorder.endRecording().dispose();
    expect(asked, ['p1']);
  });

  test('name tags: a plate by each pointer, none with tags off', () {
    final rooms = _rooms();
    final pointers = RemotePointers(rooms, room: 'nb');
    addTearDown(pointers.dispose);
    _say(rooms, {
      'k': 'pointer',
      'page': 'p1',
      'at': [5, 5],
    });
    ({int plates, int dots}) paint({required bool tags}) {
      final canvas = _CountingCanvas();
      RemotePointersPainter(
        pointers: pointers,
        viewport: ViewportController(),
        frameOf: (_) => const Rect.fromLTWH(0, 0, 800, 1000),
        tags: tags,
        plate: const Color(0xFFEEEEEE),
        label: const TextStyle(fontSize: 12),
        paperOf: (_) => PaperColor.white,
      ).paint(canvas, const Size(800, 600));
      return (plates: canvas.rrects, dots: canvas.circles);
    }

    expect(paint(tags: true), (plates: 1, dots: 2));
    expect(paint(tags: false), (plates: 0, dots: 2), reason: 'the dot stays');
  });

  test('the hover dot takes its colours from the paper, not the theme', () {
    final rooms = _rooms();
    final pointers = RemotePointers(rooms, room: 'nb');
    addTearDown(pointers.dispose);
    for (final page in ['light', 'dark']) {
      _say(rooms, {
        'k': 'pointer',
        'page': page,
        'at': [5, 5],
      }, from: 'c-$page');
    }
    final canvas = _CountingCanvas();
    RemotePointersPainter(
      pointers: pointers,
      viewport: ViewportController(),
      frameOf: (_) => const Rect.fromLTWH(0, 0, 800, 1000),
      paperOf: (id) => id == 'dark' ? PaperColor.dark : PaperColor.cream,
      tags: false,
      plate: const Color(0xFFEEEEEE),
      label: const TextStyle(fontSize: 12),
    ).paint(canvas, const Size(800, 600));
    final [lightHalo, lightDot, darkHalo, darkDot] = canvas.circleColours;
    expect(
      lightHalo.toARGB32(),
      PaperColor.cream.paper.toARGB32(),
      reason: 'ringed with the paper',
    );
    expect(darkHalo.toARGB32(), PaperColor.dark.paper.toARGB32());
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }

    expect(contrast(lightDot, PaperColor.cream.paper), greaterThan(7));
    expect(contrast(darkDot, PaperColor.dark.paper), greaterThan(7));
  });

  test('a hover goes as the page under it; a laser trail stays on the page it began on', () {
    fakeAsync((async) {
      final events = InkEvents();
      final laser = LaserTrail();
      final sent = <Map<String, Object?>>[];
      // Pages p1 (active, 0..1000 down) and p2 below it (1000..2000).
      final relay = PointerRelay(
        events: events,
        laser: laser,
        surface: () => 'p1',
        locate: (at) => at.dy < 1000 ? ('p1', at) : ('p2', at - const Offset(0, 1000)),
        send: sent.add,
        presence: ChangeNotifier(),
        anyoneThere: () => true,
      );
      addTearDown(relay.dispose);
      Map<String, Object?> last() {
        async.elapse(const Duration(milliseconds: 50));
        return sent.last;
      }

      Matcher points(String page, List<double> at) =>
          allOf(containsPair('page', page), containsPair('at', at));

      events.hovered!(const Offset(30, 400));
      expect(last(), containsPair('page', 'p1'));
      events.hovered!(const Offset(30, 1250));
      expect(last(), points('p2', [30, 250]));
      // A mouse's laser dot alone (no trail): the page under it too.
      events.hovered!(null);
      laser.hover(const Offset(40, 1100));
      expect(last(), points('p2', [40, 100]));
      laser.hover(null);
      // A trail begun on p1 and drawn on into p2: all of it on p1.
      laser
        ..config = laser.config.copyWith(mode: LaserMode.trail)
        ..down(const Offset(50, 900));
      for (var y = 950.0; y <= 1200; y += 50) {
        laser.move(Offset(50, y));
        async.elapse(const Duration(milliseconds: 50));
      }
      final trail = sent.where((m) => m['laser'] is Map && (m['laser'] as Map)['down'] == true);
      expect(trail.map((m) => m['page']).toSet(), {'p1'});
      expect(trail.last['at'], [50.0, 1200.0], reason: 'beyond its edge');
      laser.up();
      expect(last()['page'], 'p1', reason: 'its trail still fades there');
    });
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
    // Its dot takes the colours of each page's paper (the third is dark).
    final overlay = tester.widget<RemotePointersOverlay>(find.byType(RemotePointersOverlay));
    expect(
      [for (final p in s.pages.pagesOf(nb.id)) overlay.paperOf(p.id)],
      [PaperColor.white, PaperColor.cream, PaperColor.dark],
    );
    expect(session.shared.remotePointers.pointers.single.hover, const Offset(120, 80));
    expect(session.pointerRelay, isNotNull);
    expect(session.input.events.hovered, isNotNull, reason: 'someone is there: hooked in');
    s.sync.rooms.receive(LivePresence(nb.id, const []));
    await tester.pump();
    expect(session.shared.remotePointers.isEmpty, isTrue);
    expect(session.input.events.hovered, isNull);
    await closeEditor(tester);
  });

  testWidgets('in the editor: a mouse over another page than the active one points there', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester);
    final pages = s.pages.pagesOf(nb.id);
    final session = zoomSession(tester);
    final doc = session.doc!;
    s.sync.rooms.receive(
      LivePresence(nb.id, const [(connection: 'c9', deviceId: 'd9', name: 'Linux')]),
    );
    await tester.pump();
    final relayed = session.input.events.hovered!;
    final seen = <Offset?>[];
    session.input.events.hovered = (world) {
      seen.add(world);
      relayed(world);
    };
    expect(doc.activePageData.id, pages[0].id);
    final second = doc.layout.frameOf(1)!;
    final screen = doc.viewport.toScreen(second.topLeft + const Offset(60, 40));
    expect(screen.dy, lessThan(1300), reason: 'the second page shows');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: screen - const Offset(0, 1));
    await mouse.moveTo(screen);
    await tester.pump();
    expect(doc.activePageData.id, pages[0].id, reason: 'hovering activates nothing');
    final (page, at) = doc.pagePointOf(seen.last!);
    expect(page, pages[1].id);
    expect((at - const Offset(60, 40)).distance, lessThan(0.01));
    expect(session.pointerRelay.locate, isNotNull);
    s.sync.rooms.receive(LivePresence(nb.id, const []));
    await tester.pump();
    await closeEditor(tester);
  });

  testWidgets('in the zoom window: other devices\' live ink and pointers show there too', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await openZoom(tester);
    final frame = zoom.frame!;
    final at = frame.origin + const Offset(20, 10);
    void say(Map<String, Object?> data) =>
        s.sync.rooms.receive(LiveEphemeral(room: nb.id, from: 'c9', deviceId: 'd9', data: data));
    s.sync.rooms.receive(
      LivePresence(nb.id, const [(connection: 'c9', deviceId: 'd9', name: 'Linux')]),
    );
    say({
      'k': 'ink',
      's': 'w',
      'page': frame.surfaceId,
      'tool': 'ballpoint',
      'color': 0xFF112233,
      'width': 3,
      'from': 0,
      'p': [at.dx, at.dy, 0.5, at.dx + 30, at.dy + 4, 0.5],
    });
    say({
      'k': 'pointer',
      'page': frame.surfaceId,
      'at': [at.dx, at.dy],
    });
    await tester.pump();
    final paper = find.byType(ZoomBoxPaper);
    final ink = tester
        .widgetList<CustomPaint>(find.descendant(of: paper, matching: find.byType(CustomPaint)))
        .map((c) => c.painter)
        .whereType<RemoteInkPainter>()
        .single;
    expect(ink.remote.strokesOn(frame.surfaceId), hasLength(1));
    expect(ink.frameOf(frame.surfaceId), isNotNull, reason: 'the frame\'s page shows');
    expect(ink.frameOf('another page'), isNull);
    expect(ink.viewport, same(zoom.view));
    final overlay = tester.widget<RemotePointersOverlay>(
      find.descendant(of: paper, matching: find.byType(RemotePointersOverlay)),
    );
    expect(overlay.viewport, same(zoom.view));
    final canvas = _CountingCanvas();
    RemotePointersPainter(
      pointers: overlay.pointers,
      viewport: overlay.viewport,
      frameOf: overlay.frameOf,
      plate: const Color(0xFFEEEEEE),
      label: const TextStyle(fontSize: 12),
      paperOf: (_) => PaperColor.white,
    ).paint(canvas, zoom.box);
    expect(canvas.circles, 2, reason: 'the hover dot and its halo');
    expect((Offset.zero & zoom.box).contains(zoom.view.toScreen(at)), isTrue);
    s.sync.rooms.receive(LivePresence(nb.id, const []));
    await tester.pump();
    await closeEditor(tester);
  });

  testWidgets('in the editor: ⋯ → View → Name tags hides the plates, remembered', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    bool tags() => tester.widget<RemotePointersOverlay>(find.byType(RemotePointersOverlay)).tags;
    expect(s.settings.pointerTags, isTrue, reason: 'on by default');
    expect(tags(), isTrue);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Name tags'), findsNothing, reason: 'alone: nothing to label');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    s.sync.rooms.receive(
      LivePresence(nb.id, const [(connection: 'c9', deviceId: 'd9', name: 'Linux')]),
    );
    await tester.pump();
    Future<void> toggle() async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name tags'));
      await tester.pumpAndSettle();
    }

    await toggle();
    expect(tags(), isFalse);
    expect(s.settings.pointerTags, isFalse);
    await toggle();
    expect(tags(), isTrue);
    expect(s.settings.pointerTags, isTrue);
    await closeEditor(tester);
  });
}

/// Counts the plates (rounded rects) and dots (circles) a painter draws.
class _CountingCanvas implements Canvas {
  int rrects = 0;
  int circles = 0;

  /// The colours of the circles, in order.
  final List<Color> circleColours = [];

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects++;

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles++;
    circleColours.add(paint.color);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => null;
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
