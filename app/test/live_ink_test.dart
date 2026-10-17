import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/live_ink/live_ink_relay.dart';
import 'package:len/features/editor/live_ink/room_presence.dart';
import 'package:len/ink/input/ink_events.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/remote_ink.dart';
import 'package:len/ink/render/remote_ink_painter.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/sync/live_link.dart';
import 'package:len/sync/live_messages.dart';
import 'package:len/sync/live_rooms.dart';
import 'package:len/sync/remote_changes.dart';
import 'package:len/ui/app_theme.dart';

import 'support/fault_devices.dart';
import 'support/live_devices.dart';

// Real-time collaboration's first pieces over the live connection: rooms
// with presence, and the stroke being written shown on other devices as
// provisional ink until its record arrives.

/// Writes a stroke on [surface] through [live] and [events] as the editor
/// does: begun, [points] added over [over], then ended as [strokeId].
void _write(
  LiveDevices l,
  LiveInk live,
  InkEvents events,
  String surface, {
  int points = 30,
  Duration over = const Duration(milliseconds: 300),
  String? strokeId,
  bool end = true,
}) {
  live.begin(tool: InkTool.ballpoint, color: 0xFF112233, width: 3);
  live.add(const StrokePoint(0, 0, 0.5));
  events.inkBegan?.call(surface);
  final step = Duration(microseconds: over.inMicroseconds ~/ points);
  for (var i = 1; i < points; i++) {
    live.add(StrokePoint(i * 2.0, i * 1.0, 0.5));
    l.wait(step, step: step);
  }
  if (!end) return;
  live.finish();
  events.inkEnded?.call(strokeId);
}

/// Devices a (writing through `live` and `events`) and b (showing
/// `remote`) with notebook nb open.
({FaultDevice a, FaultDevice b, LiveInk live, InkEvents events, RemoteInk remote}) _pair(
  LiveDevices l,
) {
  final a = l.device('a');
  final b = l.device('b');
  l.wait(const Duration(seconds: 3));
  a.s.sync.rooms.join('nb');
  b.s.sync.rooms.join('nb');
  l.wait(const Duration(milliseconds: 100));
  final live = LiveInk();
  final events = InkEvents();
  final relay = LiveInkRelay(
    live: live,
    events: events,
    send: (data) => a.s.sync.rooms.send('nb', data),
    anyoneThere: () => a.s.sync.rooms.othersIn('nb').isNotEmpty,
  );
  addTearDown(relay.dispose);
  final remote = RemoteInk(b.s.sync.rooms, room: 'nb');
  addTearDown(remote.dispose);
  return (a: a, b: b, live: live, events: events, remote: remote);
}

void main() {
  liveTest('devices in a notebook see each other, and the stroke being written', (l) {
    final a = l.device('a');
    final b = l.device('b');
    final c = l.device('c');
    l.wait(const Duration(seconds: 3));
    a.s.sync.rooms.join('nb');
    b.s.sync.rooms.join('nb');
    c.s.sync.rooms.join('other');
    l.wait(const Duration(milliseconds: 100));
    expect(a.s.sync.rooms.othersIn('nb').single.deviceId, b.s.settings.deviceId());
    expect(a.s.sync.rooms.othersIn('nb').single.name, isNotEmpty);
    expect(b.s.sync.rooms.othersIn('nb'), hasLength(1));
    expect(c.s.sync.rooms.othersIn('other'), isEmpty);

    final live = LiveInk();
    final events = InkEvents();
    final relay = LiveInkRelay(
      live: live,
      events: events,
      send: (data) => a.s.sync.rooms.send('nb', data),
      anyoneThere: () => a.s.sync.rooms.othersIn('nb').isNotEmpty,
    );
    addTearDown(relay.dispose);
    final remote = RemoteInk(b.s.sync.rooms, room: 'nb');
    addTearDown(remote.dispose);
    var repaints = 0;
    remote.addListener(() => repaints++);

    _write(l, live, events, 'page-1', end: false);
    // Shown while it is written, a few messages a second (not one per point).
    final shown = remote.strokesOn('page-1').single;
    expect(shown.points.length, greaterThan(20));
    expect(shown.color, 0xFF112233);
    expect(shown.width, 3);
    expect(repaints, inInclusiveRange(4, 10));
    expect(remote.strokesOn('page-2'), isEmpty);

    // It ends as stroke s1: shown until that stroke arrives.
    live.finish();
    events.inkEnded?.call('s1');
    l.wait(const Duration(milliseconds: 100));
    expect(remote.strokesOn('page-1'), hasLength(1));
    remote.landed(RemoteChanges()..addItem('page-1', 'other-stroke'));
    expect(remote.strokesOn('page-1'), hasLength(1));
    remote.landed(RemoteChanges()..addItem('page-1', 's1'));
    expect(remote.strokesOn('page-1'), isEmpty);

    // Dropped without a stroke: gone at once.
    _write(l, live, events, 'page-1');
    l.wait(const Duration(milliseconds: 100));
    expect(remote.strokesOn('page-1'), isEmpty);

    // A stroke whose record never comes goes after a while, as does one
    // whose writer went quiet (left mid-stroke).
    _write(l, live, events, 'page-1', strokeId: 'lost');
    l.wait(const Duration(milliseconds: 100));
    expect(remote.strokesOn('page-1'), hasLength(1));
    l.wait(RemoteInk.afterEnd + const Duration(milliseconds: 600));
    expect(remote.strokesOn('page-1'), isEmpty);
    _write(l, live, events, 'page-1', end: false);
    expect(remote.strokesOn('page-1'), hasLength(1));
    l.wait(RemoteInk.silence + const Duration(milliseconds: 600));
    expect(remote.strokesOn('page-1'), isEmpty);
    live.finish();
    events.inkEnded?.call(null);

    // Leaving: the other side sees it alone again.
    b.s.sync.rooms.leave('nb');
    l.wait(const Duration(milliseconds: 100));
    expect(a.s.sync.rooms.othersIn('nb'), isEmpty);
  });

  liveTest('a record overtaking its end replaces the ink at once', (l) {
    final (:a, :b, :live, :events, :remote) = _pair(l);
    _write(l, live, events, 'page-1', end: false);
    expect(remote.strokesOn('page-1'), hasLength(1));
    // The stroke's record comes first (a push answered before the end got
    // through), then the end naming it: no ink waits for a record that came.
    remote.landed(RemoteChanges()..addItem('page-1', 's1'));
    expect(remote.strokesOn('page-1'), hasLength(1));
    live.finish();
    events.inkEnded?.call('s1');
    l.wait(const Duration(milliseconds: 100));
    expect(remote.strokesOn('page-1'), isEmpty);
    expect(a.s.sync.rooms.othersIn('nb'), hasLength(1));
    expect(b.s.sync.rooms.othersIn('nb'), hasLength(1));
  });

  liveTest('ink goes at once when its writer leaves or the connection drops', (l) {
    final (:a, :b, :live, :events, :remote) = _pair(l);
    _write(l, live, events, 'page-1', end: false);
    expect(remote.strokesOn('page-1'), hasLength(1));
    a.s.sync.rooms.leave('nb'); // The writer closed the notebook mid-stroke.
    l.wait(const Duration(milliseconds: 100));
    expect(remote.strokesOn('page-1'), isEmpty);
    live.finish();
    events.inkEnded?.call(null);

    a.s.sync.rooms.join('nb');
    l.wait(const Duration(milliseconds: 100));
    _write(l, live, events, 'page-1', end: false);
    expect(remote.strokesOn('page-1'), hasLength(1));
    l.network.cutLive(); // The network went: nobody is known to be there.
    l.async.flushMicrotasks();
    expect(remote.strokesOn('page-1'), isEmpty);
    expect(b.s.sync.rooms.othersIn('nb'), isEmpty);
    live.finish();
    events.inkEnded?.call(null);

    // Back: in the room again (joined anew on the new connection), and the
    // next stroke shows.
    l.until(() => b.s.sync.rooms.othersIn('nb').isNotEmpty, limit: const Duration(seconds: 10));
    _write(l, live, events, 'page-1', end: false);
    expect(remote.strokesOn('page-1'), hasLength(1));
    live.finish();
    events.inkEnded?.call(null);
  });

  liveTest('nothing is sent while nobody else is in the room', (l) {
    final a = l.device('a');
    l.wait(const Duration(seconds: 3));
    a.s.sync.rooms.join('nb');
    l.wait(const Duration(milliseconds: 100));
    final live = LiveInk();
    final events = InkEvents();
    var sent = 0;
    final relay = LiveInkRelay(
      live: live,
      events: events,
      send: (_) => sent++,
      anyoneThere: () => a.s.sync.rooms.othersIn('nb').isNotEmpty,
    );
    addTearDown(relay.dispose);
    _write(l, live, events, 'page-1', strokeId: 's');
    expect(sent, 0);
  });

  test('remote ink paints on the surfaces a view shows', () {
    final rooms = LiveRooms(LiveLink(connect: () => throw UnimplementedError(), onMessage: (_) {}))
      ..join('nb');
    final remote = RemoteInk(rooms, room: 'nb');
    addTearDown(remote.dispose);
    rooms.receive(
      const LiveEphemeral(
        room: 'nb',
        from: 'c2',
        deviceId: 'd',
        data: {
          'k': 'ink',
          's': 'x',
          'page': 'p1',
          'tool': 'ballpoint',
          'color': 0xFF000000,
          'width': 4,
          'from': 0,
          'p': [10, 10, 0.5, 60, 40, 0.5, 90, 90, 0.5],
        },
      ),
    );
    expect(remote.strokesOn('p1').single.points, hasLength(3));
    final viewport = ViewportController();
    final shown = <String>[];
    final painter = RemoteInkPainter(
      remote: remote,
      viewport: viewport,
      frameOf: (id) {
        shown.add(id);
        return id == 'p1' ? const Rect.fromLTWH(100, 0, 800, 1000) : null;
      },
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(800, 600));
    recorder.endRecording().dispose();
    expect(shown, ['p1']);
  });

  testWidgets('presence shows the other devices in the bar', (tester) async {
    final rooms = LiveRooms(LiveLink(connect: () => throw UnimplementedError(), onMessage: (_) {}))
      ..join('nb');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: RoomPresence(rooms: rooms, room: 'nb'),
          ),
        ),
      ),
    );
    expect(find.byType(Text), findsNothing);
    rooms.receive(
      const LivePresence('nb', [
        (connection: 'c1', deviceId: 'd1', name: 'Android'),
        (connection: 'c2', deviceId: 'd2', name: 'Linux'),
      ]),
    );
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.bySemanticsLabel('Also open on Android and Linux'), findsOneWidget);
    rooms.receive(
      LivePresence('nb', [
        for (var i = 0; i < 5; i++) (connection: 'c$i', deviceId: 'd$i', name: 'Windows'),
      ]),
    );
    await tester.pump();
    expect(find.text('W'), findsNWidgets(2));
    expect(find.text('+3'), findsOneWidget);
    rooms.receive(const LivePresence('nb', []));
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });
}
