import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/documents/export/export_report.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/export/pdf_export.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/thumbnails/thumbnail_renderer.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/floating_panel.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'content_documents_test.dart' show elementsOf;
import 'content_golden_test.dart' show loadFonts;
import 'content_tools_ui_test.dart'
    show key, liveElements, liveStrokes, mouseDrag, pinCanvasView, seedStroke;
import 'document_editor_test.dart' show closeEditor, pumpEditor;
import 'images_test.dart' show jpegOf, pngOf;
import 'support/selection_actions.dart';

/// Opens a canvas in the editor; [seed] runs with real async (blobs are
/// hashed in an isolate, images decoded by the engine).
Future<(AppServices, Notebook)> openImageCanvas(
  WidgetTester tester, {
  Future<void> Function(AppServices services, Notebook notebook)? seed,
  bool fonts = false,
  Size size = const Size(1280, 800),
}) async {
  if (fonts) await loadFonts();
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  final notebook = services.notebooks.create(
    title: 'Board',
    kind: NotebookKind.canvas,
    paper: PaperStyle.blank,
    coverColor: 0xFF3B5BDB,
  );
  if (seed != null) await tester.runAsync(() => seed(services, notebook));
  // World = screen coordinates: open at the origin, 100 %.
  pinCanvasView(services, notebook.id, size);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: notebook),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (services, notebook);
}

/// Stores [bytes] as a blob, decodes it fully (so painting finds it ready)
/// and adds an image element showing it.
Future<SurfaceElement> seedImage(
  AppServices s,
  String surface,
  Uint8List bytes, {
  required String id,
  required Rect rect,
  double z = -10,
  double rotation = 0,
  Rect? crop,
}) async {
  final decoded = img.decodeImage(bytes)!;
  final sha = await s.blobs.putBytes(bytes, mime: 'image/png');
  final data = ImageData(blob: sha, width: decoded.width, height: decoded.height, crop: crop);
  await s.images.load(data, decoded.width.toDouble());
  final element = SurfaceElement(
    id: id,
    surfaceId: surface,
    type: 'image',
    rect: rect,
    rotation: rotation,
    z: z,
    createdAt: 1,
    data: data.toJson(),
  );
  s.elements.save([element]);
  return element;
}

/// Lets real async work (decoding, hashing) finish while frames pump,
/// until [done] holds.
Future<void> settleReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'timed out waiting');
}

/// Makes the system clipboard hold [bytes] as an image (for this test).
void mockClipboardImage(Uint8List? bytes) {
  void answer(Uint8List? image) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        (call) async => call.method == 'image' ? image : const <Object>[],
      );
  answer(bytes);
  addTearDown(() => answer(null));
}

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(k);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Colour of pixel ([x], [y]) of an RGBA image.
Future<Color> pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  testWidgets('Ctrl+V pastes a clipboard image beneath the ink, selected; undo removes it', (
    tester,
  ) async {
    final (services, nb) = await openImageCanvas(tester);
    mockClipboardImage(pngOf(320, 160));
    expect(find.byTooltip('Insert'), findsOneWidget);
    await ctrl(tester, LogicalKeyboardKey.keyV);
    await settleReal(tester, () => liveElements(services, nb.id).isNotEmpty);
    await tester.pumpAndSettle();
    final image = liveElements(services, nb.id).single;
    expect(image.knownType, ElementType.image);
    expect(image.belowInk, isTrue);
    expect(image.rect.size, const Size(320, 160)); // Natural size: fits the view.
    expect(image.rect.center, const Offset(640, 400)); // Centre of the screen.
    final data = ImageData.fromJson(image.data);
    await tester.runAsync(() async {
      expect(await services.blobs.has(data.blob), isTrue);
      expect(services.blobs.pendingUploads(), contains(data.blob)); // Synced as a blob.
    });
    // Selected with the lasso, with image actions.
    expect(await selectionOffers(tester, 'Crop'), isTrue);
    expect(await selectionOffers(tester, 'Send to back'), isTrue);
    expect(find.byTooltip('Style'), findsNothing);
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(liveElements(services, nb.id), isEmpty);
  });

  testWidgets('Ctrl+V pastes copied ink when it is newer than the clipboard image', (tester) async {
    final (services, nb) = await openImageCanvas(
      tester,
      seed: (s, nb) async => s.strokes.save([seedStroke(nb.id)]),
    );
    mockClipboardImage(pngOf(50, 50));
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 401)]);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await tester.pump();
    await ctrl(tester, LogicalKeyboardKey.keyV);
    for (var i = 0; i < 4; i++) {
      await tester.pump(); // Reads the clipboard's image, then its text.
    }
    expect(liveStrokes(services, nb.id), hasLength(2));
    expect(liveElements(services, nb.id), isEmpty);
  });

  testWidgets('lasso taps: ink over an image wins; crop from the menu is undoable', (tester) async {
    late SurfaceElement seeded;
    final (services, nb) = await openImageCanvas(
      tester,
      fonts: true,
      seed: (s, nb) async {
        seeded = await seedImage(
          s,
          nb.id,
          jpegOf(400, 200),
          id: 'img',
          rect: const Rect.fromLTWH(100, 300, 400, 200),
        );
        s.strokes.save([seedStroke(nb.id)]); // (100, 400) → (200, 400), over the image.
      },
    );
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 400)]);
    expect(await selectionOffers(tester, 'Crop'), isFalse); // The ink.
    expect(find.byTooltip('Style'), findsOneWidget);

    await mouseDrag(tester, const [Offset(400, 450)]);
    await selectionAction(tester, 'Crop');
    expect(find.text('Done'), findsOneWidget);
    // Drag the left edge's handle a quarter in.
    await mouseDrag(tester, const [Offset(100, 400), Offset(150, 400), Offset(200, 400)]);
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/images_crop.png'));
    final reset = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Symbols.crop_free_rounded), matching: find.byType(IconButton)),
    );
    expect(reset.onPressed, isNotNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final cropped = liveElements(services, nb.id).single;
    expect(ImageData.fromJson(cropped.data).crop.left, closeTo(0.25, 1e-6));
    expect(cropped.rect, const Rect.fromLTWH(200, 300, 300, 200));
    expect(await selectionOffers(tester, 'Crop'), isTrue); // Selected again.

    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(liveElements(services, nb.id).single.rect, seeded.rect);
  });

  testWidgets('phone: the crop bar of a tall image stays clear of the bottom toolbar', (
    tester,
  ) async {
    await openImageCanvas(
      tester,
      size: const Size(390, 844),
      seed: (s, nb) async {
        await seedImage(
          s,
          nb.id,
          jpegOf(200, 400),
          id: 'img',
          rect: const Rect.fromLTWH(40, 120, 310, 620),
        );
      },
    );
    // A phone's system bars.
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(200, 400)]);
    await selectionAction(tester, 'Crop');
    final bar = tester.getRect(
      find.ancestor(of: find.text('Done'), matching: find.byType(FloatingPanel)),
    );
    final covered = tester.widget<EditorChrome>(find.byType(EditorChrome)).layout.covered;
    expect(covered.bottom, greaterThan(34)); // The toolbar is at the bottom.
    expect(bar.bottom, lessThanOrEqualTo(844 - covered.bottom), reason: 'not on the toolbar');
    expect(bar.top, greaterThan(tester.getRect(find.byTooltip('Undo (Ctrl+Z)')).bottom));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('golden: images beneath and above ink, rotated, cropped, selected', (tester) async {
    await openImageCanvas(
      tester,
      fonts: true,
      seed: (s, nb) async {
        await seedImage(
          s,
          nb.id,
          jpegOf(480, 320),
          id: 'photo',
          rect: const Rect.fromLTWH(80, 140, 480, 320),
        );
        await seedImage(
          s,
          nb.id,
          pngOf(300, 300, r: 40, g: 120, b: 220, alpha: 200),
          id: 'note',
          rect: const Rect.fromLTWH(760, 180, 300, 150),
          z: 5, // Brought to the front: above the ink.
          rotation: 0.2,
          crop: const Rect.fromLTWH(0, 0.25, 1, 0.5),
        );
        s.strokes.save([
          for (final (i, y) in [(0, 300.0), (1, 260.0)])
            Stroke(
              id: 'ink$i',
              surfaceId: nb.id,
              tool: InkTool.ballpoint,
              color: 0xFF1F2937,
              width: 6,
              points: [
                for (var x = 40.0; x <= 1200; x += 10) StrokePoint(x, y + (x % 80) / 4, 0.5),
              ],
              createdAt: 1,
            ),
        ]);
        // An image whose blob is not on this device (and no server).
        s.elements.save([
          SurfaceElement(
            id: 'missing',
            surfaceId: nb.id,
            type: 'image',
            rect: const Rect.fromLTWH(160, 540, 240, 160),
            z: -20,
            createdAt: 1,
            data: ImageData(blob: 'f' * 64, width: 240, height: 160).toJson(),
          ),
        ]);
      },
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(900, 250)]); // Select the rotated image.
    await tester.pumpAndSettle();
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/images_canvas.png'));
  });

  testWidgets('pages: a pasted image lands on the page in the middle of the screen, inside it', (
    tester,
  ) async {
    final (services, nb) = await pumpEditor(tester);
    final pages = services.pages.pagesOf(nb.id);
    mockClipboardImage(pngOf(2000, 1000));
    await ctrl(tester, LogicalKeyboardKey.keyV);
    List<SurfaceElement> all() => [for (final p in pages) ...elementsOf(services, p.id)];
    await settleReal(tester, () => all().isNotEmpty);
    final image = all().single;
    final page = pages.firstWhere((p) => p.id == image.surfaceId);
    expect(page.bounds.contains(image.rect.topLeft), isTrue);
    expect(page.bounds.contains(image.rect.bottomRight - const Offset(1e-6, 1e-6)), isTrue);
    expect(image.rect.width / image.rect.height, closeTo(2, 1e-6));
    expect(image.rect.width, lessThanOrEqualTo(page.width * 0.7 + 1e-6));
    await closeEditor(tester);
  });

  test('PNG export and covers draw images beneath the ink', () async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Doc',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    final page = services.pages.pagesOf(nb.id).first;
    final image = await seedImage(
      services,
      page.id,
      pngOf(100, 100),
      id: 'img',
      rect: const Rect.fromLTWH(100, 100, 200, 200),
    );
    services.strokes.save([
      Stroke(
        id: 'ink',
        surfaceId: page.id,
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 10,
        points: [for (var x = 120.0; x <= 280; x += 4) StrokePoint(x, 200, 0.5)],
        createdAt: 1,
      ),
    ]);
    final exporter = NotebookExporter(services);
    addTearDown(exporter.dispose);
    final png = (await ui.instantiateImageCodec(await exporter.png(page, scale: 1)));
    final frame = (await png.getNextFrame()).image;
    expect(await pixel(frame, 200, 150), const Color(0xFFDC3C28)); // The image.
    expect((await pixel(frame, 200, 200)).r, lessThan(40)); // Ink on top of it.
    expect(await pixel(frame, 50, 50), page.paperColor.paper); // Paper.

    final covers = ThumbnailRenderer(
      pages: services.pages,
      strokes: services.strokes,
      elements: services.elements,
      images: services.images,
    );
    final cover = covers.render(services.notebooks.get(nb.id)!, width: 794)!;
    expect(covers.pendingImages, isEmpty); // Decoded already.
    expect(await pixel(cover, 200, 150), const Color(0xFFDC3C28));
    expect(image.belowInk, isTrue);
  });

  test('PNG exports count the images they could not include', () async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Doc',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    final page = services.pages.pagesOf(nb.id).first;
    await seedImage(
      services,
      page.id,
      pngOf(10, 10),
      id: 'here',
      rect: const Rect.fromLTWH(10, 10, 50, 50),
    );
    // An image whose blob is on no device reachable.
    services.elements.save([
      SurfaceElement(
        id: 'gone',
        surfaceId: page.id,
        type: 'image',
        rect: const Rect.fromLTWH(100, 100, 50, 50),
        z: -10,
        createdAt: 1,
        data: const ImageData(blob: 'f00d', width: 10, height: 10).toJson(),
      ),
    ]);
    final exporter = NotebookExporter(services);
    addTearDown(exporter.dispose);
    final report = ExportReport();
    await exporter.png(page, scale: 1, report: report);
    expect(report.missingImages, 1);
    expect(report.summary, '1 image couldn’t be included');
  });

  test('PDF export embeds JPEGs as they are and other images as pixels', () async {
    final jpeg = jpegOf(64, 32), png = pngOf(16, 16, alpha: 100);
    final page = (await () async {
      final services = AppServices.create(AppDatabase.inMemory());
      addTearDown(services.dispose);
      final nb = services.notebooks.create(
        title: 'Doc',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      return services.pages.pagesOf(nb.id).first;
    }());
    SurfaceElement element(String id, String blob, {double rotation = 0, Rect? crop}) =>
        SurfaceElement(
          id: id,
          surfaceId: page.id,
          type: 'image',
          rect: const Rect.fromLTWH(50, 50, 128, 64),
          rotation: rotation,
          z: -1,
          createdAt: 1,
          data: ImageData(blob: blob, width: 64, height: 32, crop: crop).toJson(),
        );
    final bytes = await PdfExporter.build([
      ExportPage(
        page,
        const [],
        elements: [
          element('a', 'j'),
          element('b', 'j', rotation: 0.3, crop: const Rect.fromLTWH(0.1, 0.1, 0.5, 0.5)),
          element('c', 'p'),
          element('d', 'gone'),
        ],
      ),
    ], readBlob: (sha) async => {'j': jpeg, 'p': png}[sha]);
    final text = String.fromCharCodes(bytes);
    expect(RegExp(r'/Subtype\s*/Image').allMatches(text).length, 2 + 1); // JPEG once, PNG + mask.
    expect(text, contains('/DCTDecode'));
  });

  test('PDF export draws an image template (My templates) as the page paper', () async {
    final jpeg = jpegOf(60, 80);
    final sha = 'b' * 64;
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Doc',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = services.pages.pagesOf(nb.id).first.copyWith(paper: Paper.image(sha));
    Future<String> export(Map<String, Uint8List> blobs) async => String.fromCharCodes(
      await PdfExporter.build([ExportPage(page, const [])], readBlob: (b) async => blobs[b]),
    );
    expect(await export({sha: jpeg}), contains('/DCTDecode'));
    // A template whose image is missing exports plain paper.
    expect(await export({}), isNot(contains('/Subtype /Image')));
  });
}
