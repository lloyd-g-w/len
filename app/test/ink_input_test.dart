import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/highlight_snap.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

class _FakeClock extends Clock {
  int _ids = 0;

  @override
  int nowMs() => 1000;

  @override
  String newId() => 'id${_ids++}';
}

/// Builds pointer events for one pointer of a given kind.
/// Snaps a highlight into two strokes (as over two lines of text).
class _SplitSnap implements HighlightSnap {
  @override
  List<Stroke>? snap(Stroke stroke) => [
    for (var i = 0; i < 2; i++)
      Stroke(
        id: '${stroke.id}-$i',
        surfaceId: stroke.surfaceId,
        tool: stroke.tool,
        color: stroke.color,
        width: stroke.width,
        points: [for (final p in stroke.points) StrokePoint(p.x, p.y + i * 30, p.pressure)],
        createdAt: stroke.createdAt,
      ),
  ];
}

class _Pointer {
  _Pointer(this.id, this.kind, {this.buttons = 0});

  final int id;
  final PointerDeviceKind kind;
  final int buttons;

  PointerDownEvent down(Offset at) => PointerDownEvent(
    pointer: id,
    kind: kind,
    position: at,
    buttons: buttons == 0 ? kPrimaryButton : buttons,
    pressure: 0.5,
  );

  PointerMoveEvent move(Offset at) => PointerMoveEvent(
    pointer: id,
    kind: kind,
    position: at,
    buttons: buttons == 0 ? kPrimaryButton : buttons,
    pressure: 0.5,
  );

  PointerUpEvent up(Offset at) => PointerUpEvent(pointer: id, kind: kind, position: at);
}

void main() {
  late AppDatabase db;
  late StrokeRepository repo;
  late SurfaceModel model;
  late ViewportController viewport;
  late ToolSettings tools;
  late LiveInk live;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = StrokeRepository(db, deviceId: 'd');
    model = SurfaceModel(surfaceId: 's', repository: repo);
    viewport = ViewportController()..setSize(const Size(800, 600));
    tools = ToolSettings(stylusOnly: true);
    live = LiveInk();
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      clock: _FakeClock(),
    );
  });

  tearDown(() {
    model.dispose();
    db.close();
  });

  void drawLine(_Pointer p, Offset from, Offset to) {
    input
      ..handleDown(p.down(from))
      ..handleMove(p.move(Offset.lerp(from, to, 0.5)!))
      ..handleMove(p.move(to))
      ..handleUp(p.up(to));
  }

  test('stylus draws a stroke', () {
    drawLine(_Pointer(1, PointerDeviceKind.stylus), const Offset(10, 10), const Offset(100, 10));
    expect(model.loadedStrokeCount, 1);
    expect(live.isDrawing, isFalse);
  });

  test('a live stroke tells when it begins and the stroke it ended as (live ink)', () {
    final began = <String>[];
    final ended = <List<String>>[];
    input.events
      ..inkBegan = began.add
      ..inkEnded = ended.add;
    drawLine(_Pointer(1, PointerDeviceKind.stylus), const Offset(10, 10), const Offset(100, 10));
    expect(began, ['s']);
    expect(ended, hasLength(1));
    expect(model.strokeById(ended.single.single), isNotNull, reason: 'the committed stroke');
    // Erasing is no live stroke.
    final eraser = _Pointer(2, PointerDeviceKind.invertedStylus);
    drawLine(eraser, const Offset(50, -20), const Offset(50, 40));
    expect(began, hasLength(1));
    expect(ended, hasLength(1));
  });

  test('a highlight snapped to text ends naming every stroke it became', () {
    final ended = <List<String>>[];
    input
      ..events.inkEnded = ended.add
      ..highlightSnap = _SplitSnap();
    tools.tool = EditorTool.highlighter;
    drawLine(_Pointer(1, PointerDeviceKind.stylus), const Offset(10, 10), const Offset(100, 10));
    expect(ended.single, hasLength(2));
    for (final id in ended.single) {
      expect(model.strokeById(id), isNotNull, reason: 'a snapped part, committed');
    }
  });

  test('a hovering pen or mouse tells where it hovers, until it presses or leaves', () {
    final hovered = <Offset?>[];
    input.events.hovered = hovered.add;
    viewport.zoomAt(Offset.zero, 2);
    input.handleHover(
      const PointerHoverEvent(kind: PointerDeviceKind.mouse, position: Offset(40, 20)),
    );
    expect(hovered, [const Offset(20, 10)], reason: 'in world coordinates');
    final pen = _Pointer(1, PointerDeviceKind.stylus);
    input.handleDown(pen.down(const Offset(40, 20)));
    expect(hovered.last, isNull, reason: 'pressing: its ink shows');
    input
      ..handleUp(pen.up(const Offset(40, 20)))
      ..handleHover(
        const PointerHoverEvent(kind: PointerDeviceKind.stylus, position: Offset(60, 20)),
      )
      ..handleExit();
    expect(hovered.sublist(2), [const Offset(30, 10), null]);
  });

  test('S Pen side button (kPrimaryStylusButton) erases instead of drawing', () {
    drawLine(_Pointer(1, PointerDeviceKind.stylus), const Offset(10, 10), const Offset(100, 10));
    final button = _Pointer(2, PointerDeviceKind.stylus, buttons: kPrimaryStylusButton);
    drawLine(button, const Offset(50, -20), const Offset(50, 40));
    expect(model.loadedStrokeCount, 0);
  });

  test('inverted stylus erases', () {
    drawLine(_Pointer(1, PointerDeviceKind.stylus), const Offset(10, 10), const Offset(100, 10));
    drawLine(
      _Pointer(2, PointerDeviceKind.invertedStylus),
      const Offset(50, -20),
      const Offset(50, 40),
    );
    expect(model.loadedStrokeCount, 0);
  });

  test('a palm touching down while the stylus writes neither pans nor draws', () {
    final pen = _Pointer(1, PointerDeviceKind.stylus);
    final palm = _Pointer(2, PointerDeviceKind.touch);
    input
      ..handleDown(pen.down(const Offset(10, 10)))
      ..handleDown(palm.down(const Offset(300, 300)))
      ..handleMove(palm.move(const Offset(340, 320)))
      ..handleMove(pen.move(const Offset(60, 10)))
      ..handleUp(palm.up(const Offset(340, 320)))
      ..handleUp(pen.up(const Offset(60, 10)));
    expect(viewport.offset, Offset.zero);
    expect(model.loadedStrokeCount, 1);
  });

  test('a stylus landing stops fingers that were already panning', () {
    final finger = _Pointer(2, PointerDeviceKind.touch);
    input
      ..handleDown(finger.down(const Offset(300, 300)))
      ..handleMove(finger.move(const Offset(310, 300)))
      ..handleMove(finger.move(const Offset(340, 300)));
    // Past the touch slop (18), then following the finger.
    expect(viewport.offset, const Offset(40 - kTouchSlop, 0));
    input
      ..handleDown(_Pointer(1, PointerDeviceKind.stylus).down(const Offset(10, 10)))
      ..handleMove(finger.move(const Offset(400, 400)));
    expect(viewport.offset, const Offset(40 - kTouchSlop, 0));
  });

  test('stylus cancels a stroke started by the palm', () {
    tools.stylusOnly = false;
    final palm = _Pointer(2, PointerDeviceKind.touch);
    input
      ..handleDown(palm.down(const Offset(300, 300)))
      ..handleMove(palm.move(const Offset(320, 300)));
    drawLine(_Pointer(1, PointerDeviceKind.stylus), const Offset(10, 10), const Offset(100, 10));
    input.handleUp(palm.up(const Offset(320, 300)));
    expect(model.loadedStrokeCount, 1);
  });

  test('a stylus down without a previous up does not lock the pen out', () {
    final lost = _Pointer(1, PointerDeviceKind.stylus);
    input
      ..handleDown(lost.down(const Offset(10, 10)))
      ..handleMove(lost.move(const Offset(60, 10)));
    drawLine(_Pointer(2, PointerDeviceKind.stylus), const Offset(10, 100), const Offset(100, 100));
    expect(model.loadedStrokeCount, 2);
  });

  test('second finger turns a touch stroke into a pinch', () {
    tools.stylusOnly = false;
    final a = _Pointer(1, PointerDeviceKind.touch);
    final b = _Pointer(2, PointerDeviceKind.touch);
    input
      ..handleDown(a.down(const Offset(100, 100)))
      ..handleMove(a.move(const Offset(110, 100)))
      ..handleDown(b.down(const Offset(200, 100)))
      ..handleMove(b.move(const Offset(300, 100)));
    expect(viewport.scale, greaterThan(1));
    input
      ..handleUp(a.up(const Offset(110, 100)))
      ..handleUp(b.up(const Offset(300, 100)));
    expect(model.loadedStrokeCount, 0);
    expect(live.isDrawing, isFalse);
  });

  test('middle mouse button pans', () {
    final mouse = _Pointer(1, PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    input
      ..handleDown(mouse.down(const Offset(100, 100)))
      ..handleMove(mouse.move(const Offset(130, 120)))
      ..handleUp(mouse.up(const Offset(130, 120)));
    expect(viewport.offset, const Offset(30, 20));
    expect(model.loadedStrokeCount, 0);
  });

  test('switching the model mid-stroke abandons the stroke', () {
    final pen = _Pointer(1, PointerDeviceKind.stylus);
    input
      ..handleDown(pen.down(const Offset(10, 10)))
      ..handleMove(pen.move(const Offset(60, 10)));
    final other = SurfaceModel(surfaceId: 'other', repository: repo);
    addTearDown(other.dispose);
    input.model = other;
    input.handleUp(pen.up(const Offset(60, 10)));
    expect(model.loadedStrokeCount, 0);
    expect(other.loadedStrokeCount, 0);
    expect(live.isDrawing, isFalse);
  });

  group('SurfaceModel eviction', () {
    Stroke at(String id, double x) => Stroke(
      id: id,
      surfaceId: 's',
      tool: InkTool.ballpoint,
      color: 0xFF000000,
      width: 2,
      points: [StrokePoint(x, 10, 0.5), StrokePoint(x + 10, 10, 0.5)],
      createdAt: 1,
    );

    test('invalidates only evicted chunks, never everything', () {
      repo.save([for (var i = 0; i < 6; i++) at('s$i', i * 5000.0)]);
      final small = SurfaceModel(surfaceId: 's', repository: repo, maxLoadedChunks: 2);
      addTearDown(small.dispose);
      final invalidated = <Set<ChunkKey>?>[];
      small.invalidations.listen(invalidated.add);
      for (var i = 0; i < 6; i++) {
        small.ensureLoaded(Rect.fromLTWH(i * 5000.0, 0, 100, 100));
      }
      expect(invalidated, isNot(contains(null)));
      final visible = ChunkGrid.keyAt(25000, 10);
      // The last load must not have invalidated what is now on screen
      // except when that chunk was itself (re)loaded.
      expect(small.strokeById('s5'), isNotNull);
      expect(small.strokeById('s0'), isNull);
      expect(invalidated.last, isNot(contains(visible)));
    });
  });

  test('LiveInk does not repaint for an unchanged eraser cursor', () {
    var notified = 0;
    live.addListener(() => notified++);
    live
      ..showEraser(null, 5)
      ..showEraser(const Offset(1, 1), 5)
      ..showEraser(const Offset(1, 1), 5);
    expect(notified, 1);
  });

  test('a stroke shows from pen-down and records the zoom it is written at', () {
    final pen = _Pointer(1, PointerDeviceKind.stylus);
    viewport.setView(scale: 4, offset: Offset.zero);
    input.handleDown(pen.down(const Offset(10, 10)));
    expect(live.points, hasLength(1));
    expect(live.points.first.offset, const Offset(2.5, 2.5));
    expect(live.style.unit, 0.25);
    input
      ..handleMove(pen.move(const Offset(20, 10)))
      ..handleUp(pen.up(const Offset(20, 10)));
    expect(model.loadedStrokeCount, 1);
  });

  group('stylus bounce', () {
    final pen = _Pointer(1, PointerDeviceKind.stylus);

    void tap(Offset at, {required int downMs, required int upMs}) => input
      ..handleDown(pen.down(at).copyWith(timeStamp: Duration(milliseconds: downMs)))
      ..handleUp(pen.up(at).copyWith(timeStamp: Duration(milliseconds: upMs)));

    void stroke({required int downMs, required int upMs}) => input
      ..handleDown(
        pen.down(const Offset(10, 10)).copyWith(timeStamp: Duration(milliseconds: downMs)),
      )
      ..handleMove(pen.move(const Offset(60, 10)))
      ..handleMove(pen.move(const Offset(100, 10)))
      ..handleUp(pen.up(const Offset(100, 10)).copyWith(timeStamp: Duration(milliseconds: upMs)));

    test('a tiny re-contact right after a lift is dropped', () {
      stroke(downMs: 0, upMs: 300);
      tap(const Offset(103, 12), downMs: 340, upMs: 360);
      expect(model.loadedStrokeCount, 1);
    });

    test('ink shows at pen-down, also for a contact that turns out a bounce', () {
      stroke(downMs: 0, upMs: 300);
      input.handleDown(
        pen.down(const Offset(103, 12)).copyWith(timeStamp: const Duration(milliseconds: 340)),
      );
      expect(live.points, hasLength(1), reason: 'shown under the nib at once');
      input.handleUp(
        pen.up(const Offset(103, 12)).copyWith(timeStamp: const Duration(milliseconds: 360)),
      );
      expect(live.isDrawing, isFalse);
      expect(model.loadedStrokeCount, 1, reason: 'the bounce is not committed');
    });

    test('a deliberate dot placed later or elsewhere is kept', () {
      stroke(downMs: 0, upMs: 300);
      tap(const Offset(103, 12), downMs: 800, upMs: 850); // later
      tap(const Offset(300, 200), downMs: 870, upMs: 890); // elsewhere
      expect(model.loadedStrokeCount, 3);
    });
  });
}
