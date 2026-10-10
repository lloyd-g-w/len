import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/sample_source.dart';
import 'package:len/ink/input/stylus_batch.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

const device = 2 << 3 | 2; // pointer id 2, TOOL_TYPE_STYLUS
const dpr = 2.0;
const downMs = 100;

Duration ms(num t) => Duration(microseconds: (t * 1000).round());

/// A sample at logical position (x, y) (physical = × [dpr]) at [t] ms.
StylusSample sample(double t, double x, double y, {double pressure = 0.5}) =>
    StylusSample(timeUs: t * 1000, x: x * dpr, y: y * dpr, pressure: pressure);

/// The batch of the MotionEvent at [t] ms: [historical] then the current
/// sample (x, y).
StylusBatch batch(
  int t,
  List<StylusSample> historical,
  double x,
  double y, {
  int downAt = downMs,
  int dev = device,
}) => StylusBatch(
  device: dev,
  downTimeUs: downAt * 1000.0,
  eventTimeUs: t * 1000.0,
  samples: [...historical, sample(t.toDouble(), x, y)],
);

PointerDownEvent down(double x, double y, {int t = downMs, int pointer = 1}) => PointerDownEvent(
  pointer: pointer,
  device: device,
  kind: PointerDeviceKind.stylus,
  timeStamp: ms(t),
  position: Offset(x, y),
  pressure: 0.5,
  pressureMin: 0,
  pressureMax: 1,
);

PointerMoveEvent move(int t, double x, double y, {int pointer = 1}) => PointerMoveEvent(
  pointer: pointer,
  device: device,
  kind: PointerDeviceKind.stylus,
  timeStamp: ms(t),
  position: Offset(x, y),
  pressure: 0.5,
  pressureMin: 0,
  pressureMax: 1,
);

PointerUpEvent up(int t, double x, double y, {int pointer = 1}) => PointerUpEvent(
  pointer: pointer,
  device: device,
  kind: PointerDeviceKind.stylus,
  timeStamp: ms(t),
  position: Offset(x, y),
);

class _Clock extends Clock {
  int _ids = 0;
  @override
  int nowMs() => 1000;
  @override
  String newId() => 'id${_ids++}';
}

void main() {
  group('StylusBatchCodec', () {
    test('round-trips batches', () {
      final batches = [
        batch(120, [sample(112, 1, 2, pressure: 0.25), sample(116, 3, 4)], 5, 6),
        batch(136, const [], 7, 8, dev: 9),
      ];
      final decoded = StylusBatchCodec.decode(StylusBatchCodec.encode(batches));
      expect(decoded, hasLength(2));
      expect(decoded[0].device, device);
      expect(decoded[0].downTimeUs, downMs * 1000);
      expect(decoded[0].eventTimeUs, 120000);
      expect(decoded[0].samples.map((s) => (s.timeUs, s.x, s.y)), [
        (112000, 2, 4),
        (116000, 6, 8),
        (120000, 10, 12),
      ]);
      expect(decoded[0].samples.first.pressure, 0.25);
      expect(decoded[0].historical, hasLength(2));
      expect(decoded[1].device, 9);
    });

    test('ignores malformed and unknown messages', () {
      final good = StylusBatchCodec.encode([
        batch(120, [sample(112, 1, 2)], 5, 6),
      ]);
      final truncated = ByteData.sublistView(good, 0, good.lengthInBytes - 4);
      expect(StylusBatchCodec.decode(truncated), isEmpty);
      expect(StylusBatchCodec.decode(ByteData(4)), isEmpty);
      final future = ByteData.sublistView(Uint8List.fromList(good.buffer.asUint8List()))
        ..setInt32(0, 99, Endian.little);
      expect(StylusBatchCodec.decode(future), isEmpty);
    });
  });

  group('StylusSampleMerger', () {
    late StylusBatchBuffer buffer;
    late StylusSampleMerger merger;

    setUp(() {
      buffer = StylusBatchBuffer();
      merger = StylusSampleMerger(buffer, devicePixelRatio: () => dpr);
    });

    List<double> xs(List<PointerSample> s) => [for (final p in s) p.localPosition.dx];

    test('inserts historical samples before the event they precede', () {
      buffer.addAll([
        batch(116, [sample(104, 1, 0), sample(108, 2, 0), sample(112, 3, 0)], 4, 0),
      ]);
      merger.begin(down(0, 0));
      final s = merger.between(move(116, 4, 0));
      expect(xs(s), [1, 2, 3]);
      expect(s.map((p) => p.timeStamp), [ms(104), ms(108), ms(112)]);
    });

    test('a late batch is skipped; later ones still merge, never twice', () {
      merger.begin(down(0, 0));
      expect(merger.between(move(116, 4, 0)), isEmpty, reason: 'batch not here yet');
      final late = batch(116, [sample(108, 2, 0)], 4, 0);
      final next = batch(132, [sample(124, 6, 0)], 8, 0);
      buffer.addAll([late, next, next]); // also a duplicate
      expect(xs(merger.between(move(132, 8, 0))), [6]);
      expect(merger.between(move(132, 8, 0)), isEmpty, reason: 'same event again');
    });

    test('an event Flutter never delivered contributes all its samples', () {
      buffer.addAll([
        batch(116, [sample(108, 2, 0)], 4, 0),
        batch(132, [sample(124, 6, 0)], 8, 0),
      ]);
      merger.begin(down(0, 0));
      expect(xs(merger.between(move(132, 8, 0))), [2, 4, 6]);
    });

    test('ignores other contacts, other pointers and anything after end', () {
      buffer.addAll([
        batch(116, [sample(108, 2, 0)], 4, 0, downAt: 50), // an older contact
        batch(116, [sample(108, 9, 0)], 4, 0, dev: device + 8), // another pointer
      ]);
      merger.begin(down(0, 0));
      expect(merger.between(move(116, 4, 0)), isEmpty);
      buffer.addAll([
        batch(132, [sample(124, 6, 0)], 8, 0),
      ]);
      merger.end();
      expect(merger.between(move(132, 8, 0)), isEmpty);
    });

    test('never steps back in time within a contact', () {
      buffer.addAll([
        batch(116, [sample(108, 2, 0)], 4, 0),
        batch(132, [sample(104, 1, 0), sample(124, 6, 0)], 8, 0),
      ]);
      merger.begin(down(0, 0));
      expect(xs(merger.between(move(116, 4, 0))), [2]);
      expect(xs(merger.between(move(132, 8, 0))), [6]);
    });

    test('touch and mouse contacts get nothing', () {
      buffer.addAll([
        batch(116, [sample(108, 2, 0)], 4, 0),
      ]);
      merger.begin(
        PointerDownEvent(device: device, kind: PointerDeviceKind.touch, timeStamp: ms(downMs)),
      );
      expect(merger.between(move(116, 4, 0)), isEmpty);
    });

    test('converts physical view pixels to the event\'s local space', () {
      // The listener sits 40 × 20 logical px into the view.
      final transform = Matrix4.translationValues(-40, -20, 0);
      buffer.addAll([
        batch(116, [sample(108, 90, 100)], 100, 100),
      ]);
      merger.begin(down(80, 100).transformed(transform));
      final event = move(116, 100, 100).transformed(transform);
      expect(event.localPosition, const Offset(60, 80));
      final s = merger.between(event);
      expect(s.single.localPosition, const Offset(50, 80));
    });
  });

  group('InkInputController with dense samples', () {
    late AppDatabase db;
    late SurfaceModel model;
    late LiveInk live;
    late StylusBatchBuffer buffer;
    late ViewportController viewport;
    late InkInputController input;

    setUp(() {
      db = AppDatabase.inMemory();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
      );
      live = LiveInk();
      buffer = StylusBatchBuffer();
      viewport = ViewportController()..setSize(const Size(800, 600));
      input = InkInputController(
        model: model,
        viewport: viewport,
        tools: ToolSettings(stylusOnly: true),
        live: live,
        clock: _Clock(),
        samples: StylusSampleMerger(buffer, devicePixelRatio: () => dpr),
      );
    });

    tearDown(() {
      model.dispose();
      db.close();
    });

    List<Stroke> committed() =>
        model.strokesNear(const Rect.fromLTWH(-500, -500, 1000, 1000)).toList();

    List<double> liveXs() => [for (final p in live.points) p.x];

    test('fills the gaps between pointer events, in order', () {
      input.handleDown(down(0, 0));
      buffer.addAll([
        batch(116, [sample(105, 5, 0), sample(110, 10, 0)], 15, 0),
      ]);
      input.handleMove(move(116, 15, 0));
      buffer.addAll([
        batch(132, [sample(121, 20, 0), sample(127, 25, 0)], 30, 0),
      ]);
      input.handleMove(move(132, 30, 0));
      expect(liveXs(), [0, 5, 10, 15, 20, 25, 30]);
    });

    test('missing batches degrade to the pointer events alone', () {
      input
        ..handleDown(down(0, 0))
        ..handleMove(move(116, 15, 0))
        ..handleMove(move(132, 30, 0));
      buffer.addAll([
        batch(116, [sample(110, 10, 0)], 15, 0),
      ]); // too late
      input.handleMove(move(148, 45, 0));
      expect(liveXs(), [0, 15, 30, 45]);
    });

    test('samples before pen-up are kept; nothing after it', () {
      input
        ..handleDown(down(0, 0))
        ..handleMove(move(116, 15, 0));
      buffer.addAll([
        batch(132, [sample(124, 20, 0)], 15, 0),
      ]);
      input.handleUp(up(132, 15, 0));
      final stroke = committed().single;
      expect([for (final p in stroke.points) p.x], [0, 15, 20]);
      buffer.addAll([
        batch(148, [sample(140, 30, 0)], 40, 0),
      ]);
      input.handleMove(move(148, 40, 0));
      expect(live.isDrawing, isFalse);
      expect(committed().single.points, hasLength(3));
    });

    test('positions go through the viewport into world coordinates', () {
      viewport
        ..zoomAt(Offset.zero, 2)
        ..panBy(const Offset(10, 0));
      input.handleDown(down(10, 0));
      buffer.addAll([
        batch(116, [sample(108, 30, 4)], 50, 0),
      ]);
      input.handleMove(move(116, 50, 0));
      final p = live.points[1];
      expect(Offset(p.x, p.y), viewport.toWorld(const Offset(30, 4)));
      expect(p.x, 10);
    });

    test('sample pressure is normalised like the event\'s', () {
      input.handleDown(down(0, 0));
      buffer.addAll([
        batch(116, [sample(108, 10, 0, pressure: 1.0)], 20, 0),
      ]);
      input.handleMove(move(116, 20, 0));
      // The pressure filter blends 0.5 (down) with the sample's 1.0.
      expect(live.points[1].pressure, greaterThan(0.6));
      expect(live.points[1].pressure, lessThan(1.0));
    });

    test('erasing ignores samples', () {
      input
        ..handleDown(
          PointerDownEvent(
            pointer: 3,
            device: device,
            kind: PointerDeviceKind.invertedStylus,
            timeStamp: ms(downMs),
          ),
        )
        ..handleUp(
          PointerUpEvent(
            pointer: 3,
            device: device,
            kind: PointerDeviceKind.invertedStylus,
            timeStamp: ms(116),
          ),
        );
      expect(model.loadedStrokeCount, 0);
      expect(<StrokePoint>[...live.points], isEmpty);
    });
  });
}
