import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/ink/render/content_painter.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_kind.dart';

import 'canvas_export_test.dart' show pixel;

const ink = 0xFF1F2937, yellow = 0xFFFACC15;

/// A 200×200 square on [surface] outlined in [ink], filled with [fill].
Stroke square(String surface, {int? fill = yellow}) => Stroke(
  id: 'sq',
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: ink,
  width: 3,
  points: ShapeBuilder.points(
    ShapeBuilder.outline(ShapeKind.rectangle, Offset.zero, const Offset(200, 200)),
  ),
  createdAt: 1,
  style: ShapeBuilder.styleFor(const StrokeStyle()).withFill(fill),
);

/// The decompressed content streams of [pdf].
List<String> contentStreams(Uint8List pdf) {
  final text = latin1.decode(pdf);
  final out = <String>[];
  for (final m in RegExp(r'stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', m.end);
    if (end < 0) continue;
    final raw = pdf.sublist(m.end, end);
    try {
      out.add(latin1.decode(zlib.decode(raw)));
    } on FormatException {
      out.add(latin1.decode(raw));
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppServices services;
  late NotebookExporter exporter;

  setUp(() {
    services = AppServices.create(AppDatabase.inMemory());
    exporter = NotebookExporter(services);
  });
  tearDown(() async {
    await exporter.dispose();
    services.dispose();
  });

  Notebook board() => services.notebooks.create(
    title: 'Board',
    kind: NotebookKind.canvas,
    paper: PaperStyle.blank,
    coverColor: 0,
  );

  test('the PDF fills the shape with a vector path beneath its outline', () async {
    final nb = board();
    services.strokes.save([square(nb.id)]);
    final pdf = await exporter.canvasPdf(exporter.canvasPage(nb)!, title: nb.title);
    final content = contentStreams(pdf).join('\n');
    // The fill colour is set, then a polygon (moves and lines) is filled.
    final rg = RegExp(r'([\d.]+) ([\d.]+) ([\d.]+) rg\s').allMatches(content).toList();
    final fill = ui.Color(yellow);
    final at = rg.indexWhere(
      (m) =>
          (double.parse(m[1]!) - fill.r).abs() < 0.01 &&
          (double.parse(m[2]!) - fill.g).abs() < 0.01 &&
          (double.parse(m[3]!) - fill.b).abs() < 0.01,
    );
    expect(at, isNot(-1), reason: 'the fill colour is set');
    final path = content.substring(rg[at].end, rg[at + 1].start);
    expect(path, contains(' m'));
    expect(RegExp(r' l\s').allMatches(path).length, greaterThan(3));
    expect(path, matches(RegExp(r'\sf\s')));
    // The outline comes after, in the ink's colour.
    expect((double.parse(rg[at + 1][1]!) - ui.Color(ink).r).abs(), lessThan(0.01));
  });

  test('the PNG export, thumbnails and previews paint the fill', () async {
    final nb = board();
    services.strokes.save([square(nb.id)]);
    final canvas = exporter.canvasPage(nb)!;
    final png = await exporter.canvasPng(canvas, scale: 1);
    final centre = (100 - canvas.worldOrigin!.dx).round();
    final inside = await pixel(png, centre, (100 - canvas.worldOrigin!.dy).round());
    expect(inside.toARGB32(), yellow);

    // Thumbnails sketch thin ink as plain lines: the fill is there too.
    for (final sketch in [false, true]) {
      final recorder = ui.PictureRecorder();
      ContentPainter.paint(
        ui.Canvas(recorder),
        [square(nb.id)],
        const [],
        pixelScale: 0.1,
        sketchThin: sketch,
      );
      final image = await recorder.endRecording().toImage(200, 200);
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final i = (100 * 200 + 100) * 4;
      expect(
        [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)],
        [0xFA, 0xCC, 0x15],
        reason: 'sketch: $sketch',
      );
      image.dispose();
    }
  });
}
