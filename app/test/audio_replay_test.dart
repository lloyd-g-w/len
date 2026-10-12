import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/audio/recording_overview.dart';
import 'package:len/features/audio/replay/ink_replay_painter.dart';
import 'package:len/features/audio/replay/replay_target.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import 'data_test.dart' show FakeClock;

Stroke _stroke(String id, Offset at, int createdAt) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: [StrokePoint(at.dx, at.dy, 0.5), StrokePoint(at.dx + 40, at.dy + 4, 0.5)],
  createdAt: createdAt,
);

SurfaceElement _text(String id, Rect rect, int createdAt) => SurfaceElement(
  id: id,
  surfaceId: 's',
  type: ElementType.text.name,
  rect: rect,
  z: 1,
  createdAt: createdAt,
  data: const TextData(text: 'Mitosis').toJson(),
);

SurfaceElement _image(String id, Rect rect, int createdAt) => SurfaceElement(
  id: id,
  surfaceId: 's',
  type: ElementType.image.name,
  rect: rect,
  z: -1,
  createdAt: createdAt,
  data: ImageData(blob: 'ab' * 32, width: 10, height: 10).toJson(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ink is stamped when the pen touches down, not when it lifts', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final clock = FakeClock()..now = 50000;
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    addTearDown(model.dispose);
    final viewport = ViewportController()..setSize(const Size(800, 600));
    final input = InkInputController(
      model: model,
      viewport: viewport,
      tools: ToolSettings(stylusOnly: false),
      live: LiveInk(),
      clock: clock,
    );
    PointerEvent at(Offset p, {bool down = false, bool up = false}) => up
        ? PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: p)
        : down
        ? PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: p, pressure: 0.5)
        : PointerMoveEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: p, pressure: 0.5);
    input.handleDown(at(const Offset(100, 100), down: true) as PointerDownEvent);
    for (var i = 1; i <= 20; i++) {
      clock.now += 150; // A slow, 3 s stroke.
      input.handleMove(at(Offset(100.0 + i * 10, 100.0 + i)) as PointerMoveEvent);
    }
    input.handleUp(at(const Offset(300, 120), up: true) as PointerUpEvent);
    final stroke = model.strokesNear(const Rect.fromLTWH(0, 0, 800, 600)).single;
    expect(stroke.createdAt, 50000);

    // Replayed from a recording that began at 49 s: the stroke shows from
    // 1 s in — while it was being written — not only once it was done.
    final timeline = RecordingTimeline(const [RecordingSegment(49000, 10000)]);
    expect(timeline.positionOf(stroke.createdAt), 1000);
    expect(timeline.wallTimeAt(2000) >= stroke.createdAt, isTrue);
  });

  group('veils', () {
    late AppDatabase db;
    late SurfaceModel model;
    const ChunkKey key = (x: 0, y: 0);
    const paper = Color(0xFFFFFFFF);

    setUp(() {
      db = AppDatabase.inMemory();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
        elementRepository: ElementRepository(db, deviceId: 'd'),
      );
      model.commit(
        InkEdit(
          added: [
            _stroke('a', const Offset(10, 10), 1000),
            _stroke('b', const Offset(10, 60), 3000),
          ],
          addedElements: [
            _text('t', const Rect.fromLTWH(100, 100, 120, 40), 5000),
            _image('i', const Rect.fromLTWH(0, 200, 100, 80), 7000),
          ],
        ),
      );
    });
    tearDown(() {
      model.dispose();
      db.close();
    });

    test('cover strokes, text boxes and images made after the moment heard', () {
      final veils = ReplayVeils();
      // Before everything: one veil over all of it.
      expect(veils.pictureFor(model, key, 0, paper), isNotNull);
      // After the strokes, before the text box and the image.
      final mid = veils.pictureFor(model, key, 4000, paper);
      expect(mid, isNotNull);
      // Same set of future content: the cached picture is reused.
      expect(veils.pictureFor(model, key, 4500, paper), same(mid));
      // Only the image is still to come.
      final late = veils.pictureFor(model, key, 6000, paper);
      expect(late, isNot(same(mid)));
      // Everything made: nothing to veil.
      expect(veils.pictureFor(model, key, 8000, paper), isNull);
      // A trimmed recording kept up to 6 s: the image (7 s) was made after
      // it and stays visible; only the text box (5 s) is veiled at 4.5 s.
      final trimmed = veils.pictureFor(model, key, 4500, paper, until: 6000);
      expect(trimmed, isNot(same(mid)));
      expect(veils.pictureFor(model, key, 6000, paper, until: 6000), isNull);
      // Hidden content (being edited) is not veiled.
      model.setHidden({'i'});
      expect(veils.pictureFor(model, key, 6000, paper), isNull);
      veils.clear();
    });

    test('tapping a text box or image finds when it was made', () {
      final viewport = ViewportController()..setSize(const Size(800, 600));
      final target = ReplayTarget.canvas(model, viewport, PaperColor.white);
      expect(target.createdAtUnder(const Offset(30, 61)), 3000); // Stroke b.
      expect(target.createdAtUnder(const Offset(150, 120)), 5000); // Text box.
      expect(target.createdAtUnder(const Offset(50, 240)), 7000); // Image.
      expect(target.createdAtUnder(const Offset(600, 500)), isNull);
    });
  });

  test('content times of a notebook during a recording (pages and canvas)', () {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'N',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(nb.id).first.id;
    Stroke on(String surface, String id, int at) => Stroke(
      id: id,
      surfaceId: surface,
      tool: InkTool.ballpoint,
      color: 0,
      width: 2,
      points: const [StrokePoint(0, 0, 0.5)],
      createdAt: at,
    );
    s.strokes.save([
      on(page, 'a', 100),
      on(page, 'b', 900),
      on(page, 'c', 5000),
      on('x', 'd', 500),
    ]);
    s.elements.save([
      SurfaceElement(id: 'e', surfaceId: page, type: 'text', rect: Rect.zero, z: 1, createdAt: 700),
    ]);
    s.strokes.delete(['b']);
    expect(s.recordings.contentTimes(nb.id, from: 0, to: 1000), [100, 700]);

    // Mapped onto the recording and grouped into bursts of writing.
    final ink = InkActivity.of(
      Recording(
        id: 'r',
        notebookId: nb.id,
        parts: [RecordingPart('ab' * 32, 1000)],
        durationMs: 1000,
        startedAt: 0,
        title: 'Lecture',
        mime: Recording.adtsMime,
        updatedAt: 1,
      ),
      s.recordings.contentTimes(nb.id, from: 0, to: 1000),
    );
    expect(ink.positions, [100, 700]);
    expect(ink.markers, [100]);
  });
}
