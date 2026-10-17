import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/raster_batch.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

/// One rendered frame: RGBA bytes of [width] × [height] device pixels.
class Frame {
  Frame(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;

  /// Writes the frame as a PNG (debugging: `INK_FRAMES_DUMP=dir`).
  Future<void> save(String path) async {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, done.complete);
    final image = await done.future;
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    File(path).writeAsBytesSync(png.buffer.asUint8List());
  }

  /// How dark pixel [i] is (0 white … 255 black), from its least bright
  /// channel, so coloured ink counts too.
  int darkness(int i) {
    final o = i * 4;
    var low = bytes[o];
    if (bytes[o + 1] < low) low = bytes[o + 1];
    if (bytes[o + 2] < low) low = bytes[o + 2];
    return 255 - low;
  }
}

/// Pixels of [a] that are ink (darker than [ink]) where [b] is at least
/// [by] lighter, in the pixel and every pixel within [near] of it: ink
/// that frame [b] lost (a resampled or sharper rendering of the same ink
/// moves edges by a pixel, which is no loss). Only pixels [within] (if
/// given) and not within [except] (device pixels) are counted.
int lostInk(
  Frame a,
  Frame b, {
  int ink = 96,
  int by = 64,
  int near = 1,
  List<Rect> except = const [],
  Rect? within,
}) {
  var lost = 0;
  final w = a.width, h = a.height;
  bool kept(int x, int y, int da) {
    for (var dy = -near; dy <= near; dy++) {
      for (var dx = -near; dx <= near; dx++) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        if (da - b.darkness(ny * w + nx) < by) return true;
      }
    }
    return false;
  }

  for (var i = 0; i < w * h; i++) {
    final da = a.darkness(i);
    if (da < ink || da - b.darkness(i) < by) continue;
    final x = i % w, y = i ~/ w;
    if (within != null && !within.contains(Offset(x + 0.5, y + 0.5))) continue;
    if (kept(x, y, da)) continue;
    if (except.isNotEmpty && except.any((r) => r.contains(Offset(x + 0.5, y + 0.5)))) continue;
    lost++;
  }
  return lost;
}

/// Draws strokes live through a [viewport] over committed ink (painted by
/// [paintInk]) and records every frame, as the editor's three layers do:
/// the live highlighter beneath the committed ink, the live pen over it.
class InkFrames {
  InkFrames({
    required this.size,
    required this.dpr,
    required this.viewport,
    required this.paintInk,
    this.clip,
  });

  final Size size;
  final double dpr;
  final ViewportController viewport;
  final void Function(Canvas canvas) paintInk;
  final Rect? clip;
  final LiveInk live = LiveInk();

  /// Renders the current frame.
  Future<Frame> frame() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(dpr)
      ..drawColor(Colors.white, BlendMode.src);
    LiveInkPainter(live: live, viewport: viewport, clip: clip, belowInk: true).paint(canvas, size);
    paintInk(canvas);
    LiveInkPainter(live: live, viewport: viewport, clip: clip).paint(canvas, size);
    final picture = recorder.endRecording();
    final w = (size.width * dpr).ceil(), h = (size.height * dpr).ceil();
    final image = await picture.toImage(w, h);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return Frame(bytes.buffer.asUint8List(), w, h);
  }

  /// Draws [points] (world) live with [tool], [per] points a frame, and
  /// returns the frames (the last one is the last live frame).
  Future<List<Frame>> draw(
    List<StrokePoint> points, {
    InkTool tool = InkTool.ballpoint,
    double? width,
    int per = 8,
    double? streamline,
    Future<void> Function(int frame)? between,
  }) async {
    final config = PenConfig.defaultsFor(tool);
    final style = config.styleFor(tool).copyWith(unit: 1 / viewport.scale, streamline: streamline);
    live.begin(tool: tool, color: config.color, width: width ?? config.width, style: style);
    final frames = <Frame>[];
    for (var n = 0; n < points.length; n += per) {
      live.addAll(points.sublist(n, (n + per).clamp(0, points.length)));
      await between?.call(frames.length);
      frames.add(await frame());
    }
    return frames;
  }

  /// Lifts the pen as `InkDrawing` commits: the live outline is adopted and
  /// the stroke added to [model] in the same frame.
  Stroke lift(SurfaceModel model, {String id = 'new', int createdAt = 1 << 41}) {
    final committed = live.finish();
    final stroke = Stroke(
      id: id,
      surfaceId: model.surfaceId,
      tool: live.tool,
      color: live.color,
      width: live.width,
      style: live.style,
      points: committed,
      createdAt: createdAt,
    );
    final path = LiveStrokeBuilder.finishLive(
      live,
      committed,
      width: stroke.width,
      style: stroke.style,
    );
    if (path != null) StrokeRenderer.adopt(stroke, path);
    model.addStroke(stroke);
    return stroke;
  }

  /// Renders frames, letting renders progress [step] between them, until
  /// [settled] (at most [limit] frames).
  Future<List<Frame>> until(
    bool Function() settled, {
    int limit = 120,
    Duration step = const Duration(milliseconds: 4),
  }) async {
    final frames = <Frame>[];
    for (var i = 0; i < limit && !settled(); i++) {
      await Future<void>.delayed(step);
      frames.add(await frame());
    }
    expect(settled(), isTrue, reason: 'the ink settled');
    frames.add(await frame());
    return frames;
  }

  /// The device-pixel box around [world] point, [radius] logical px.
  Rect around(Offset world, double radius) =>
      Rect.fromCircle(center: viewport.toScreen(world) * dpr, radius: radius * dpr);
}

/// Expects that no frame of [frames] lost ink the one before it had
/// (beyond [allowed] pixels, outside [except]).
Future<void> expectNoLostInk(
  List<Frame> frames, {
  int allowed = 0,
  List<Rect> except = const [],
  String what = 'frame',
}) async {
  for (var k = 1; k < frames.length; k++) {
    final lost = lostInk(frames[k - 1], frames[k], except: except);
    final dir = Platform.environment['INK_FRAMES_DUMP'];
    if (lost > allowed && dir != null) {
      await frames[k - 1].save('$dir/${what.replaceAll(' ', '_')}_${k - 1}.png');
      await frames[k].save('$dir/${what.replaceAll(' ', '_')}_$k.png');
    }
    expect(lost, lessThanOrEqualTo(allowed), reason: '$what $k lost $lost px of ink');
  }
}

/// A [RasterBatch] whose renders wait while [hold] is set (a busy raster
/// thread), and go once it is cleared ([release]).
class HeldBatch extends RasterBatch {
  HeldBatch() : super(batching: false);

  bool hold = false;
  final List<Completer<void>> _waiting = [];

  /// Renders waiting.
  int get waiting => _waiting.length;

  @override
  Future<RasterImage> rasterize(ui.Picture picture, int width, int height) async {
    if (hold) {
      final gate = Completer<void>();
      _waiting.add(gate);
      await gate.future;
    }
    return super.rasterize(picture, width, height);
  }

  /// Lets the waiting renders go (and later ones at once).
  void release() {
    hold = false;
    for (final gate in _waiting) {
      gate.complete();
    }
    _waiting.clear();
  }
}
