// The pen never flickers at pen-up: the first frame with the committed
// stroke shows the ink the last live frame showed, edge pixels included,
// at every stabiliser and zoom, from a stylus and from a mouse, through
// the real input pipeline. Only the end may change: the pen-up hook
// trimmed, the last pressures settled, the stabilised line catching up
// with the pen from where the last frame's provisional tip ended, a
// mouse's provisional tip (`LiveInk.tip`) becoming ink.
//
// Two measures. Exact: on every edge pixel of the live outline, 4 × 4
// samples (as a GPU's multisampling covers a pixel), none inside the last
// live outline and outside the committed one — a pixel the committed
// stroke draws lighter. Rendered: the frames as the test rasteriser draws
// them, no pixel lighter by more than a little (it approximates curves,
// and the same area drawn with other curves or contours comes out a
// little different; before, at 30 % and 110 %, an edge pixel mid-stroke
// went from 99 to 59).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/mouse_smoother.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/replay.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import 'support/ink_frames.dart';
import 'support/mouse_writing.dart';

const double _dpr = 2.625;

/// The logical px of the screen rendered.
const Rect _crop = Rect.fromLTWH(0, 0, 330, 80);

/// A rendered frame and the live outline drawn in it (world).
typedef _Shot = ({Frame frame, Path? outline});

/// Renders [_crop] of the screen: [committed] strokes and [live] ink as the
/// editor layers them, at [_dpr].
Future<_Shot> _render(ViewportController viewport, LiveInk live, Iterable<Stroke> committed) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(_dpr)
    ..translate(-_crop.left, -_crop.top)
    ..drawColor(Colors.white, BlendMode.src);
  final size = Size(_crop.right, _crop.bottom);
  LiveInkPainter(live: live, viewport: viewport, belowInk: true).paint(canvas, size);
  canvas
    ..save()
    ..translate(viewport.offset.dx, viewport.offset.dy)
    ..scale(viewport.scale);
  for (final s in committed) {
    StrokeRenderer.draw(canvas, s);
  }
  canvas.restore();
  final painter = LiveInkPainter(live: live, viewport: viewport)..paint(canvas, size);
  final picture = recorder.endRecording();
  final w = (_crop.width * _dpr).ceil(), h = (_crop.height * _dpr).ceil();
  final image = await picture.toImage(w, h);
  picture.dispose();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return (frame: Frame(bytes.buffer.asUint8List(), w, h), outline: painter.debugOutline?.combined);
}

/// One stroke's pen-up: the last live frame and the first with [stroke]
/// committed, where the pen lifted and where the last live frame's ink
/// ended (device px; the stabiliser holds it back from the pen) and the
/// device px → world mapping.
class _Handover {
  _Handover(this.live, this.committed, this.stroke, StrokePoint tip, ViewportController v)
    : end = (v.toScreen(stroke.points.last.offset) - _crop.topLeft) * _dpr,
      tip = (v.toScreen(tip.offset) - _crop.topLeft) * _dpr,
      _scale = v.scale,
      _offset = v.offset;

  final _Shot live;
  final Frame committed;
  final Stroke stroke;
  final Offset end, tip;
  final double _scale;
  final Offset _offset;

  /// The world point at device px ([x], [y]) of the frames.
  Offset world(double x, double y) => (Offset(x, y) / _dpr + _crop.topLeft - _offset) / _scale;
}

/// Replays [recording] and renders the frames around each pen-up.
Future<List<_Handover>> _handovers(InputRecording recording) async {
  final db = AppDatabase.inMemory();
  final model = SurfaceModel(
    surfaceId: 's',
    repository: StrokeRepository(db, deviceId: 'd'),
  );
  final live = LiveInk();
  final viewport = ViewportController(minScale: 0.01, maxScale: 64);
  final driver = ReplayDriver(recording, model: model, live: live, viewport: viewport);
  // The stabiliser's string is live only, by design gone at pen-up
  // (`stabiliser_string_test.dart`): not drawn here.
  driver.tools.showStabiliserString = false;
  final committed = <Stroke>[];
  final out = <_Handover>[];
  _Shot? last;
  StrokePoint? tip;
  try {
    for (var step = driver.step(); step != null; step = driver.step()) {
      if (step.committed.isNotEmpty) {
        committed.addAll(step.committed);
        final shot = await _render(viewport, live, committed);
        out.add(_Handover(last!, shot.frame, step.committed.single, tip!, viewport));
      }
      last = live.isDrawing ? await _render(viewport, live, committed) : null;
      tip = live.isDrawing ? live.points.last : null;
    }
  } finally {
    model.dispose();
    live.dispose();
    viewport.dispose();
    db.close();
  }
  return out;
}

/// Samples (4 × 4 a device pixel) on the edge pixels of [h]'s last live
/// frame that the live outline covers and the committed one does not,
/// outside [except] (device px).
int _lostSamples(_Handover h, List<Rect> except) {
  final live = h.live.outline!, committed = StrokeRenderer.pathOf(h.stroke);
  final frame = h.live.frame;
  var lost = 0;
  for (var i = 0; i < frame.width * frame.height; i++) {
    final d = frame.darkness(i);
    if (d == 0 || d == 255) continue;
    final x = i % frame.width, y = i ~/ frame.width;
    if (except.any((r) => r.contains(Offset(x + 0.5, y + 0.5)))) continue;
    for (var u = 0; u < 4; u++) {
      for (var v = 0; v < 4; v++) {
        final p = h.world(x + (u + 0.5) / 4, y + (v + 0.5) / 4);
        if (live.contains(p) && !committed.contains(p)) lost++;
      }
    }
  }
  return lost;
}

void main() {
  // Handwriting with curves, cusps and straight bars (screen px).
  final paths = ownerFormula(origin: const Offset(10, 60), h: 40);
  for (final kind in [PointerDeviceKind.stylus, PointerDeviceKind.mouse]) {
    final mouse = kind == PointerDeviceKind.mouse;
    for (final stabiliser in [0.0, 0.3, 0.6, 1.0]) {
      for (final zoom in [0.5, 1.0, 1.1, 2.625, 4.0]) {
        // Where the ink may change at pen-up (logical px around the lift
        // and the last frame's tip): the end (its rules reach a width back
        // from a finished end, half a width from a moving tip, plus the
        // cap: a width and a half of a wide pen zoomed in), and a mouse's
        // provisional tip and the line it runs on from.
        final zone = mouse && stabiliser == 0
            ? 12 + MouseSmoother.lagOf(MouseSmoother.minSigma)
            : math.max(8.0, 1.5 * const PenSettings().width * zoom);
        testWidgets('${kind.name}, stabiliser $stabiliser, ${zoom}x: pen-up shows the same ink', (
          tester,
        ) async {
          await tester.runAsync(() async {
            final rec = mouseRecording(
              paths,
              model: MouseModel(hz: mouse ? 125 : 240, quantum: mouse ? 1 : 0),
              speed: 250,
              pen: const PenSettings().copyWith(streamline: stabiliser),
              zoom: zoom,
              kind: kind,
            );
            final handovers = await _handovers(rec.recording);
            expect(handovers, hasLength(paths.length));
            for (final (k, h) in handovers.indexed) {
              // The end, and the provisional tip the last frame's ink ended
              // in, held back from the pen by the stabiliser.
              final end = Rect.fromCircle(center: h.end, radius: zone * _dpr);
              final tip = Rect.fromCircle(center: h.tip, radius: zone * _dpr);
              final samples = _lostSamples(h, [end, tip]);
              final pixels = lostInk(
                h.live.frame,
                h.committed,
                near: 0,
                by: 48,
                except: [end, tip],
              );
              final dir = Platform.environment['INK_FRAMES_DUMP'];
              if ((samples > 0 || pixels > 0) && dir != null) {
                await h.live.frame.save('$dir/handover_${k}_live.png');
                await h.committed.save('$dir/handover_${k}_committed.png');
              }
              expect(samples, 0, reason: 'stroke $k: $samples samples of ink lost');
              expect(pixels, 0, reason: 'stroke $k: $pixels px lighter');
            }
          });
        });
      }
    }
  }
}
