// One highlighter stroke is one even layer, like one pass of a marker:
// where it crosses itself it does not darken; where two strokes overlap,
// they do. Committed ink (vector and tiles), live ink, PNG and PDF export
// agree (INK_LAB.md "Pen end styles").
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/render/tiles/ink_tile_cache.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;
import 'support/canvas_fixtures.dart';

List<StrokePoint> _polyline(List<Offset> corners) => [
  for (var k = 0; k + 1 < corners.length; k++)
    for (var i = 0; i < 40; i++)
      StrokePoint(
        corners[k].dx + (corners[k + 1].dx - corners[k].dx) * i / 40,
        corners[k].dy + (corners[k + 1].dy - corners[k].dy) * i / 40,
        0.5,
      ),
  StrokePoint(corners.last.dx, corners.last.dy, 0.5),
];

Stroke _highlighter(String id, String surface, List<Offset> corners, int createdAt) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.highlighter,
  color: 0xFF2563EB,
  width: 16,
  points: _polyline(corners),
  createdAt: createdAt,
);

/// Right along y = 100, up, left and down through itself at (150, 100).
const _loop = [
  Offset(50, 100),
  Offset(250, 100),
  Offset(250, 30),
  Offset(150, 30),
  Offset(150, 170),
];

/// Another stroke across the first at (210, 100).
const _across = [Offset(210, 50), Offset(210, 160)];

/// Where to look (world): the loop on its own, where it crosses itself,
/// where the other stroke crosses it.
const _single = Offset(90, 100), _self = Offset(150, 100), _two = Offset(210, 100);

/// The colours at [_single], [_self] and [_two] in an image of the world
/// mapped by [toPixel].
Future<List<ui.Color>> _colours(ui.Image image, Offset Function(Offset) toPixel) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [
    for (final w in [_single, _self, _two])
      () {
        final p = toPixel(w);
        final i = (p.dy.round() * image.width + p.dx.round()) * 4;
        return ui.Color.fromARGB(
          data.getUint8(i + 3),
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
      }(),
  ];
}

void _expectOneLayer(List<ui.Color> c, String where) {
  double d(ui.Color a, ui.Color b) =>
      [(a.r - b.r).abs(), (a.g - b.g).abs(), (a.b - b.b).abs()].reduce((x, y) => x > y ? x : y);
  final [single, self, two] = c;
  expect(d(single, self), lessThan(3 / 255), reason: '$where: crossing itself $self vs $single');
  expect(d(single, two), greaterThan(30 / 255), reason: '$where: two strokes $two vs $single');
}

Future<ui.Image> _paint(Size size, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final strokes = [_highlighter('a', 's', _loop, 1), _highlighter('b', 's', _across, 2)];
  const size = Size(320, 220);

  testWidgets('committed ink, as vectors and as tiles', (tester) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
        reader: MemoryStrokeReader(strokes),
        maxLoadedChunks: 1 << 20,
      );
      final viewport = ViewportController(minScale: 0.01)..setSize(size);
      model.ensureLoaded(viewport.visibleWorld);
      final pictures = ChunkPictureCache(model, devicePixelRatio: 1);
      final tiles = InkTileCache(pictures, settleDelay: const Duration(milliseconds: 20));
      CommittedInkPainter painter({required bool tiled}) => CommittedInkPainter(
        model: model,
        cache: pictures,
        viewport: viewport,
        tiles: tiled ? tiles : null,
        devicePixelRatio: 1,
      );
      final vector = await _paint(size, (c) => painter(tiled: false).paint(c, size));
      _expectOneLayer(await _colours(vector, (w) => w), 'vector');
      for (var i = 0; i < 50 && (i == 0 || tiles.isBusy); i++) {
        await _paint(size, (c) => painter(tiled: true).paint(c, size));
        await settle(() => !tiles.isBusy);
      }
      final tiled = await _paint(size, (c) => painter(tiled: true).paint(c, size));
      expect(tiles.lastPaint.images, greaterThan(0));
      _expectOneLayer(await _colours(tiled, (w) => w), 'tiles');
      tiles.dispose();
      pictures.dispose();
      model.dispose();
      db.close();
    });
  });

  testWidgets('live ink', (tester) async {
    await tester.runAsync(() async {
      final loop = strokes[0];
      final live = LiveInk()
        ..begin(tool: loop.tool, color: loop.color, width: loop.width, style: loop.style);
      final viewport = ViewportController(minScale: 0.01)..setSize(size);
      final painter = LiveInkPainter(live: live, viewport: viewport, belowInk: true);
      // Drawn as it grows, so part of it is frozen and the rest a tail.
      for (var n = 0; n < loop.points.length; n += 3) {
        live.addAll(loop.points.sublist(n, (n + 3).clamp(0, loop.points.length)));
        await _paint(size, (c) => painter.paint(c, size));
      }
      final image = await _paint(size, (c) {
        painter.paint(c, size);
        StrokeRenderer.draw(c, strokes[1]);
      });
      _expectOneLayer(await _colours(image, (w) => w), 'live');
    });
  });

  group('export', () {
    late AppServices services;
    late NotebookExporter exporter;
    late Notebook nb;
    setUpAll(() {
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      services = AppServices.create(AppDatabase.inMemory());
      exporter = NotebookExporter(services);
      nb = services.notebooks.create(
        title: 'Board',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      services.strokes.save([
        for (final s in strokes) _highlighter(s.id, nb.id, s.id == 'a' ? _loop : _across, 1),
      ]);
    });
    tearDown(() async {
      await exporter.dispose();
      services.dispose();
    });

    test('PNG', () async {
      final page = exporter.canvasPage(nb)!;
      final png = await exporter.canvasPng(page, scale: 1);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      _expectOneLayer(await _colours(image, (w) => w - page.worldOrigin!), 'PNG');
    });

    test(
      'PDF',
      skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
      () async {
        final page = exporter.canvasPage(nb)!;
        final pdf = await exporter.canvasPdf(page, title: nb.title);
        final doc = await PdfDocument.openData(Uint8List.fromList(pdf));
        final w = page.page.width.ceil(), h = page.page.height.ceil();
        final rendered = (await doc.pages[0].render(fullWidth: w * 1.0, fullHeight: h * 1.0))!;
        final image = await rendered.createImage();
        rendered.dispose();
        _expectOneLayer(await _colours(image, (p) => p - page.worldOrigin!), 'PDF');
        await doc.dispose();
      },
    );
  });
}
