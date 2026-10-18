@Tags(['perf'])
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/mouse_smoother.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/replay.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

import '../content_tools_ui_test.dart' show openCanvas;
import 'support/frame_counts.dart';

/// Mouse ink (smoothed on the screen with the stroke's stabiliser,
/// `MouseSmoother`; at 0 a provisional tip runs on to the mouse): the cost
/// of a mouse move must stay flat with the stroke's length — no work
/// proportional to the stroke per move. Timed early in a stroke and late
/// in a 20,000-move one, through the real input pipeline (controller,
/// smoother, sampler, live ink) plus the live outline as the painter
/// builds it each frame, and in the editor (widgets rebuilt, paints).
void main() {
  // Strokes are written after the frame (`SurfaceModel.writeBehind`).
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Whole-pixel mouse positions, one a millisecond: cursive loops moving
  /// on along a line (~3 px a move).
  Offset at(int i) => Offset(
    (100 + i * 0.4 + 20 * math.sin(i / 7)).roundToDouble(),
    (300 + 20 * math.cos(i / 7)).roundToDouble(),
  );

  test('smoother alone: µs per move early and late in a long stroke', () {
    for (final stabiliser in [0.0, 0.3, 1.0]) {
      var early = double.infinity, late = double.infinity, tip = 0;
      for (var round = 0; round < 5; round++) {
        final s = MouseSmoother((_, _) {})..begin(at(0), 0, stabiliser: stabiliser);
        double window(int from, int to) {
          final w = Stopwatch()..start();
          for (var i = from; i < to; i++) {
            s.add(at(i), i);
            if (stabiliser == 0) s.tip();
          }
          return w.elapsedMicroseconds / (to - from);
        }

        for (var i = 1; i < 200; i++) {
          s.add(at(i), i);
        }
        final e = window(200, 2200);
        for (var i = 2200; i < 18000; i++) {
          s.add(at(i), i);
        }
        final l = window(18000, 20000);
        early = math.min(early, e);
        late = math.min(late, l);
        tip = s.tip().length;
      }
      _report(
        'smoother, stabiliser ${(stabiliser * 100).round()} %: '
        '${early.toStringAsFixed(2)} µs/move at 200–2,200, ${late.toStringAsFixed(2)} at '
        '18,000–20,000${stabiliser == 0 ? ' (tip() each move, $tip points)' : ''}',
      );
      expect(late, lessThan(early * 3 + 2));
    }
  });

  test('pipeline: µs per move (input, live outline, one path) early and late', () async {
    for (final stabiliser in [0.0, 0.3, 1.0]) {
      final best = <String, double>{};
      void keep(String k, double v) => best[k] = math.min(best[k] ?? double.infinity, v);
      for (var round = 0; round < 3; round++) {
        final p = _Pipeline(stabiliser);
        p.input.handleDown(
          PointerDownEvent(kind: PointerDeviceKind.mouse, position: at(0), buttons: kPrimaryButton),
        );
        late LiveOutline outline;
        Future<void> moves(int from, int to, [String? label]) async {
          final input = Stopwatch(), build = Stopwatch(), one = Stopwatch(), copy = Stopwatch();
          for (var i = from; i < to; i++) {
            final e = PointerMoveEvent(
              kind: PointerDeviceKind.mouse,
              position: at(i),
              timeStamp: Duration(milliseconds: i),
              buttons: kPrimaryButton,
            );
            input.start();
            p.input.handleMove(e);
            input.stop();
            // As `LiveInkPainter` does each frame (a frame a move: the worst).
            build.start();
            outline = LiveStrokeBuilder.livePath(p.live);
            build.stop();
            // Filled in one path, as `LiveInkPainter` does (before: the
            // frozen part appended into a new path, verb by verb).
            one.start();
            outline.combined;
            one.stop();
            copy.start();
            Path()
              ..addPath(outline.frozen ?? outline.tail, Offset.zero)
              ..addPath(outline.tail, Offset.zero);
            copy.stop();
          }
          if (label == null) return;
          final n = to - from;
          keep('input $label', input.elapsedMicroseconds / n);
          keep('build $label', build.elapsedMicroseconds / n);
          keep('one $label', one.elapsedMicroseconds / n);
          keep('copy $label', copy.elapsedMicroseconds / n);
          keep('raster $label', await _rasterMs((c) => c.drawPath(outline.combined, _ink)));
        }

        await moves(1, 200);
        await moves(200, 1200, 'early');
        await moves(1200, 19000);
        await moves(19000, 20000, 'late');
        keep('points', p.live.points.length.toDouble());
        final (up, write) = p.up(at(20000), 20000);
        keep('pen-up', up);
        keep('write', write);
        p.dispose();

        // Pen-up after a short stroke, for comparison.
        final short = _Pipeline(stabiliser);
        short.input.handleDown(
          PointerDownEvent(kind: PointerDeviceKind.mouse, position: at(0), buttons: kPrimaryButton),
        );
        for (var i = 1; i < 1200; i++) {
          short.input.handleMove(
            PointerMoveEvent(
              kind: PointerDeviceKind.mouse,
              position: at(i),
              timeStamp: Duration(milliseconds: i),
              buttons: kPrimaryButton,
            ),
          );
          if (i % 8 == 0) LiveStrokeBuilder.livePath(short.live).combined;
        }
        keep('short pen-up', short.up(at(1200), 1200).$1);
        short.dispose();
      }
      String f(String k) =>
          '${best['$k early']!.toStringAsFixed(2)} → '
          '${best['$k late']!.toStringAsFixed(2)}';
      _report(
        'pipeline, stabiliser ${(stabiliser * 100).round()} % (${best['points']!.round()} live '
        'points at the end), moves 200–1,200 → 19,000–20,000: input ${f('input')} µs/move, '
        'live outline ${f('build')} µs/move, in one path (`LiveOutline.combined`) ${f('one')} '
        'µs/move (appended into a new path: ${f('copy')}); rasterising it ${f('raster')} ms; '
        'pen-up ${best['pen-up']!.toStringAsFixed(1)} ms (after 1,200 moves: '
        '${best['short pen-up']!.toStringAsFixed(1)}), written after the frame '
        '${best['write']!.toStringAsFixed(1)} ms',
      );
      // Pen-up costs about the same whatever the stroke's length: its
      // outline continues the live one, its chunks were traced as it was
      // drawn and it is written after the frame.
      expect(best['pen-up']!, lessThan(best['short pen-up']! * 3 + 5));
      // The outline filled in one path copies its frozen part each frame
      // (`LiveOutline.combined`): linear by design, reported above.
      for (final k in ['input', 'build']) {
        expect(best['$k late']!, lessThan(best['$k early']! * 3 + 5), reason: k);
      }
    }
  });

  testWidgets('editor: a mouse move at 30 % early and late in a long stroke', (tester) async {
    await openCanvas(tester);
    final gesture = await tester.startGesture(at(0), kind: PointerDeviceKind.mouse);
    var i = 0;
    Future<void> step(int _) async {
      i++;
      await gesture.moveTo(at(i), timeStamp: Duration(milliseconds: i));
      await tester.pump(const Duration(milliseconds: 8));
    }

    final early = await countFrames(step, 200, warmUp: 100);
    while (i < 6000) {
      await gesture.moveTo(at(++i), timeStamp: Duration(milliseconds: i));
      if (i % 4 == 0) await tester.pump(const Duration(milliseconds: 4));
    }
    final late = await countFrames(step, 200, warmUp: 0);
    _report('editor, a move a frame, moves 100–300: $early');
    _report('editor, a move a frame, moves 6,000–6,200: $late');
    await gesture.up();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('editor: the frames after pen-up, a short and a 20,000-move stroke', (tester) async {
    await openCanvas(tester);
    final frames = <int, List<double>>{};
    final pumps = <int, List<double>>{};
    // A short and a long stroke to warm up, then the same measured.
    for (final (round, moves) in [(0, 1200), (1, 20000), (2, 1200), (3, 20000)]) {
      // Each stroke lower than the last, on a fresh part of the canvas.
      Offset where(int i) => at(i) + Offset(0, round * 60.0);
      final gesture = await tester.startGesture(where(0), kind: PointerDeviceKind.mouse);
      for (var i = 1; i <= moves; i++) {
        await gesture.moveTo(where(i), timeStamp: Duration(milliseconds: i));
        if (i % 4 == 0) await tester.pump(const Duration(milliseconds: 4));
      }
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up(timeStamp: Duration(milliseconds: moves + 1));
      final f = frames[moves] = [], p = pumps[moves] = [];
      for (var i = 0; i < 4; i++) {
        final pump = Stopwatch()..start();
        f.add(await _frameMs(tester));
        p.add(pump.elapsedMicroseconds / 1000);
      }
      await tester.pump(const Duration(seconds: 1));
    }
    String list(List<double> ms) => ms.map((m) => m.toStringAsFixed(1)).join(', ');
    _report(
      'editor, the first four frames after pen-up: after 1,200 moves ${list(frames[1200]!)} ms '
      '(pumps ${list(pumps[1200]!)}), after 20,000 moves ${list(frames[20000]!)} ms '
      '(pumps ${list(pumps[20000]!)}; between the frames the harness runs the engine\'s '
      'snapshots of the stroke\'s tiles, on the raster thread in the app)',
    );
    // The frames after pen-up do not grow with the stroke's length.
    final short = frames[1200]!.reduce(math.max), long = frames[20000]!.reduce(math.max);
    expect(long, lessThan(short * 2 + 4));
  });
}

/// The frame a 16 ms pump draws (ms): from its first frame callback to
/// the end of drawing it, without the timers the pump runs before it.
Future<double> _frameMs(WidgetTester tester) async {
  final frame = Stopwatch();
  var us = 0;
  tester.binding
    ..scheduleFrameCallback((_) => frame.start())
    ..addPostFrameCallback((_) => us = frame.elapsedMicroseconds)
    ..scheduleFrame();
  await tester.pump(const Duration(milliseconds: 16));
  return us / 1000;
}

/// The input pipeline of a canvas, without widgets, drawing with the
/// default pen at [stabiliser].
final _ink = Paint()..color = const Color(0xFF1A2233);

/// Milliseconds to rasterise what [paint] draws on a 1280 × 800 screen
/// (best of 5), net of an empty frame.
Future<double> _rasterMs(void Function(Canvas)? paint) async {
  var best = double.infinity;
  for (var i = 0; i < 5; i++) {
    final w = Stopwatch()..start();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    paint?.call(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1280, 800);
    best = math.min(best, w.elapsedMicroseconds / 1000);
    image.dispose();
    picture.dispose();
  }
  return paint == null ? best : best - await _rasterMs(null);
}

class _Pipeline {
  _Pipeline(double stabiliser) {
    ReplayDriver.applyPen(tools, const PenSettings().copyWith(streamline: stabiliser));
  }

  final db = AppDatabase.inMemory();

  /// Written after the frame, as in the editor.
  late final model = SurfaceModel(
    surfaceId: 's',
    repository: StrokeRepository(db, deviceId: 'd'),
    writeBehind: true,
  );
  final viewport = ViewportController()..setSize(const Size(1280, 800));
  final tools = ToolSettings(stylusOnly: false);
  final live = LiveInk();
  late final input = InkInputController(model: model, viewport: viewport, tools: tools, live: live);

  /// Lifts the mouse at [position] at [ms]: milliseconds the pen-up took
  /// and the write after the frame.
  (double, double) up(Offset position, int ms) {
    final w = Stopwatch()..start();
    input.handleUp(
      PointerUpEvent(
        kind: PointerDeviceKind.mouse,
        position: position,
        timeStamp: Duration(milliseconds: ms),
      ),
    );
    final up = w.elapsedMicroseconds / 1000;
    w.reset();
    model.flush();
    return (up, w.elapsedMicroseconds / 1000);
  }

  void dispose() {
    model.dispose();
    live.dispose();
    db.close();
  }
}

void _report(String line) {
  // ignore: avoid_print
  print('mouse ink perf: $line');
}
