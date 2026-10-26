// Writes the stabiliser's sheets (docs/inklab/stabiliser/after_*.png; opt-in):
//
//   flutter test test/inklab/tools/stabiliser_sheets_test.dart \
//     --dart-define=STABILISER_SHEETS=<output dir>
//
// Fast cursive and a slow, shaky line, one row per stabiliser (0, 30, 60,
// 100 %; skipped without the define): left the committed stroke over the pen's path (red), right a
// live frame part way through, with the string and the pen (red dot).
@Tags(['inklab'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import '../sim/cases.dart';
import '../sim/digitiser.dart';
import '../sim/pen_motion.dart';
import '../stabiliser_speed_test.dart' show fastCursive;
import '../stabiliser_test.dart' show shakyLine;

const String _out = String.fromEnvironment('STABILISER_SHEETS');

/// A panel's size (image px).
const Size _panel = Size(600, 270);

/// Renders one sheet of [motion]: [crop] (screen px) of each panel at [k]
/// image px per screen px, the live frame at [liveAt] of the stroke.
Future<void> _sheet(String file, PenMotion motion, Rect crop, double k, double liveAt) async {
  const settings = [0.0, 0.3, 0.6, 1.0];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  final red = Paint()
    ..color = const Color(0xFFE5383B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1 / k;
  for (final (row, s) in settings.indexed) {
    final rec = SimCase('sheet', '', [
      SimContact(motion, start: 0),
    ]).record(defaultPen.copyWith(streamline: s));
    final samples = rawContacts(rec.recording).single.samples;
    final liveUs = samples.first.timeUs + (samples.last.timeUs - samples.first.timeUs) * liveAt;
    final db = AppDatabase.inMemory();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    final live = LiveInk();
    final viewport = ViewportController(minScale: 0.01, maxScale: 64);
    final driver = ReplayDriver(rec.recording, model: model, live: live, viewport: viewport);
    void panel(int column, void Function() paint) {
      canvas
        ..save()
        ..translate(column * _panel.width, row * _panel.height)
        ..clipRect(Offset.zero & _panel)
        ..scale(k)
        ..translate(-crop.left, -crop.top);
      paint();
      canvas.restore();
    }

    var shown = false;
    for (var step = driver.step(); step != null; step = driver.step()) {
      if (!shown && live.isDrawing && step.newestEventUs >= liveUs) {
        shown = true;
        final newest = step.newestEventUs;
        final pen = samples.lastWhere((x) => x.timeUs <= newest).position;
        panel(1, () {
          LiveInkPainter(live: live, viewport: viewport, belowInk: true).paint(canvas, crop.size);
          LiveInkPainter(live: live, viewport: viewport).paint(canvas, crop.size);
          canvas.drawCircle(pen, 1.5, Paint()..color = const Color(0xFFE5383B));
        });
      }
      for (final stroke in step.committed) {
        panel(0, () {
          canvas
            ..save()
            ..translate(viewport.offset.dx, viewport.offset.dy)
            ..scale(viewport.scale);
          StrokeRenderer.draw(canvas, stroke);
          canvas.restore();
          canvas.drawPath(Path()..addPolygon(rec.truth.single.path, false), red);
        });
      }
    }
    model.dispose();
    live.dispose();
    viewport.dispose();
    db.close();
  }
  final w = (_panel.width * 2).round(), h = (_panel.height * settings.length).round();
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  File('$_out/$file').writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  testWidgets('stabiliser sheets', (tester) async {
    await tester.runAsync(() async {
      Directory(_out).createSync(recursive: true);
      Rect around(PenMotion m, double k) {
        var r = Rect.fromCircle(center: m.at(0), radius: 0);
        for (var i = 0; i <= 400; i++) {
          r = r.expandToInclude(Rect.fromCircle(center: m.at(m.duration * i / 400), radius: 0));
        }
        final size = _panel / k;
        return Rect.fromCenter(center: r.center, width: size.width, height: size.height);
      }

      const fastK = 2.5, slowK = 1.8;
      await _sheet('after_fast.png', fastCursive, around(fastCursive, fastK), fastK, 0.6);
      await _sheet('after_slow.png', shakyLine, around(shakyLine, slowK), slowK, 0.6);
      expect(math.max(fastK, slowK), greaterThan(0));
    });
  }, skip: _out.isEmpty);
}
