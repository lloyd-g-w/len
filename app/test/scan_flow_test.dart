import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/scan/scan_corner_editor.dart';
import 'package:len/features/documents/scan/scan_import.dart';
import 'package:len/features/documents/scan/scan_job.dart';
import 'package:len/features/documents/scan/scan_page_strip.dart';
import 'package:len/features/documents/scan/scan_photo.dart';
import 'package:len/features/documents/scan/scan_result_view.dart';
import 'package:len/features/documents/scan/scan_screen.dart';
import 'package:len/features/documents/scan/scan_sources.dart';
import 'package:len/features/editor/editor_screen.dart';

import 'import_flow_ui_test.dart' show openFromLibrary;
import 'support/real_async.dart';
import 'support/tester_clock.dart';
import 'ui_library_test.dart' show pumpLibrary;

/// A photo of a light page (a slightly skewed quad) on a dark desk.
Uint8List deskPhoto({int width = 360, int height = 480}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(40, 44, 52));
  img.fillPolygon(
    image,
    vertices: [
      img.Point(width * 0.2, height * 0.12),
      img.Point(width * 0.8, height * 0.15),
      img.Point(width * 0.78, height * 0.9),
      img.Point(width * 0.22, height * 0.88),
    ],
    color: img.ColorRgb8(236, 234, 228),
  );
  // Some "ink".
  img.fillRect(
    image,
    x1: width * 0.3 ~/ 1,
    y1: height * 0.4 ~/ 1,
    x2: width * 0.6 ~/ 1,
    y2: height * 0.42 ~/ 1,
    color: img.ColorRgb8(20, 30, 90),
  );
  return img.encodePng(image);
}

XFile photoFile(String name, [Uint8List? bytes]) =>
    XFile.fromData(bytes ?? deskPhoto(), name: name, path: '/tmp/$name', mimeType: 'image/png');

/// Scan sources answering with [picks] in turn (then nothing) and, with
/// [camera], a camera.
ScanSources fakeSources({List<List<XFile>> picks = const [], List<XFile>? camera}) {
  final queue = [...picks];
  final shots = camera == null ? null : [...camera];
  return ScanSources(
    pick: () async => queue.isEmpty ? <XFile>[] : queue.removeAt(0),
    camera: shots == null ? null : () async => shots.isEmpty ? null : shots.removeAt(0),
  );
}

ScanScreenTester scan(WidgetTester tester) => ScanScreenTester(tester);

/// Drives the scan screen.
class ScanScreenTester {
  ScanScreenTester(this.tester);

  final WidgetTester tester;

  /// The pages in the screen's session.
  int get pages => tester.widget<ScanScreen>(find.byType(ScanScreen)).session.pages.length;

  /// Waits until [n] pages are loaded and their previews rendered.
  Future<void> untilPages(int n) => pumpUntil(
    tester,
    () {
      final session = tester.widget<ScanScreen>(find.byType(ScanScreen)).session;
      return session.pages.length == n &&
          session.pages.every((p) => p.preview != null) &&
          (n == 0 || session.display != null);
    },
    stable: 2,
    reason: '$n scanned pages',
  );

  Future<void> tap(Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Opens ⊕▾ in the library and picks "Scan document…".
Future<void> scanFromLibrary(WidgetTester tester) async {
  await tester.tap(find.byTooltip('New'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan document…'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(() => ScanSources.debugSources = null);
  // Without a camera (as on the desktop and the web).
  final noCamera = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('without a camera: picked photos become a new notebook of scanned pages', (
    tester,
  ) async {
    // Titled after the app's date.
    final services = await pumpLibrary(
      tester,
      services: AppServices.create(
        AppDatabase.inMemory(),
        clock: FixedClock(DateTime(2026, 10, 14, 9)),
      ),
    );
    ScanSources.debugSources = fakeSources(
      picks: [
        [photoFile('page1.png')],
      ],
    );
    await scanFromLibrary(tester);
    final s = scan(tester);
    await s.untilPages(1);
    expect(find.byType(ScanCornerEditor), findsOneWidget);
    expect(find.text('1 page'), findsOneWidget);

    // The page was found: its corners are not the photo's.
    final session = tester.widget<ScanScreen>(find.byType(ScanScreen)).session;
    final page = session.current!;
    expect(page.photo.detected, isNotNull);
    expect(page.quad, isNot(page.photo.bounds));
    expect(page.quad.topLeft.dx, closeTo(360 * 0.2, 12));

    // Rotate it and pick black and white.
    await s.tap(find.text('B&W'));
    expect(session.filter, ScanFilter.blackWhite);
    await s.tap(find.text('Rotate'));
    expect(page.turns, 1);
    await s.untilPages(1);

    await s.tap(find.text('Create notebook'));
    await pumpUntil(tester, () => find.byType(EditorScreen).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    final notebook = services.notebooks.list().single;
    expect(notebook.title, 'Scan Oct 14');
    expect(notebook.kind, NotebookKind.paged);
    final pages = services.pages.pagesOf(notebook.id);
    expect(pages, hasLength(1));
    final background = pages.single.background!;
    expect(background.kind, PageBackgroundKind.image);
    expect(await tester.runAsync(() => services.blobs.has(background.blob)), isTrue);
    // Turned a quarter: the page is now landscape.
    expect(pages.single.size.width, greaterThan(pages.single.size.height));
  }, variant: noCamera);

  testWidgets('the look picked last time is where the next scan starts', (tester) async {
    final services = await pumpLibrary(tester);
    services.settings.scanFilter = ScanFilter.greyscale.name;
    ScanSources.debugSources = fakeSources(
      picks: [
        [photoFile('page.png')],
      ],
    );
    await scanFromLibrary(tester);
    final s = scan(tester);
    await s.untilPages(1);
    final session = tester.widget<ScanScreen>(find.byType(ScanScreen)).session;
    expect(session.filter, ScanFilter.greyscale);
    final look = tester.widget<SegmentedButton<ScanFilter>>(
      find.byKey(const ValueKey('scan-filter')),
    );
    expect(look.selected, {ScanFilter.greyscale});

    // Picked even if the scan is then discarded.
    await s.tap(find.text('B&W'));
    expect(services.settings.scanFilter, ScanFilter.blackWhite.name);
    await s.tap(find.byTooltip('Close'));
    await s.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(services.settings.scanFilter, ScanFilter.blackWhite.name);
  }, variant: noCamera);

  testWidgets('tapping the current page shows it cleaned up, large; tapping that, the corners', (
    tester,
  ) async {
    await pumpLibrary(tester);
    ScanSources.debugSources = fakeSources(
      picks: [
        [photoFile('a.png'), photoFile('b.png')],
      ],
    );
    await scanFromLibrary(tester);
    final s = scan(tester);
    await s.untilPages(2);
    final session = tester.widget<ScanScreen>(find.byType(ScanScreen)).session;
    expect(session.index, 1);

    await s.tap(find.bySemanticsLabel('Page 2'));
    expect(session.showsResult, isTrue);
    expect(find.byType(ScanResultView), findsOneWidget);
    expect(find.byType(ScanCornerEditor), findsNothing);
    await pumpUntil(tester, () => session.result != null, reason: 'the large result');
    final small = session.current!.preview!, large = session.result!;
    expect(large.width, greaterThan(small.width));
    expect(large.width / large.height, closeTo(small.width / small.height, 0.02));

    // It follows the look and turns.
    await s.tap(find.text('Rotate'));
    await pumpUntil(tester, () => session.result!.width > session.result!.height);

    // Another page keeps the view; tapping the result goes back to the corners.
    await s.tap(find.bySemanticsLabel('Page 1'));
    expect(session.index, 0);
    expect(session.showsResult, isTrue);
    await pumpUntil(tester, () => session.result != null);
    await s.tap(find.byType(ScanResultView));
    expect(session.showsResult, isFalse);
    expect(session.result, isNull);
    expect(find.byType(ScanCornerEditor), findsOneWidget);

    // Preview and Space switch too.
    await s.tap(find.text('Preview'));
    expect(session.showsResult, isTrue);
    await pumpUntil(tester, () => session.result != null);
    await s.tap(find.text('Preview'));
    expect(session.showsResult, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(session.showsResult, isTrue);
    await pumpUntil(tester, () => session.result != null);
    await s.tap(find.byTooltip('Close'));
    await s.tap(find.text('Discard'));
    await tester.pumpAndSettle();
  }, variant: noCamera);

  testWidgets('pages reorder by dragging them in the strip and with Ctrl+arrows', (tester) async {
    await pumpLibrary(tester);
    ScanSources.debugSources = fakeSources(
      picks: [
        [photoFile('a.png'), photoFile('b.png'), photoFile('c.png')],
      ],
    );
    await scanFromLibrary(tester);
    final s = scan(tester);
    await s.untilPages(3);
    final session = tester.widget<ScanScreen>(find.byType(ScanScreen)).session;
    final [a, b, c] = session.pages;
    expect(session.current, c);

    // Drag page 1 past page 3 (with a mouse, at once).
    final from = tester.getCenter(find.bySemanticsLabel('Page 1'));
    final to = tester.getCenter(find.bySemanticsLabel('Page 3'));
    final drag = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(Offset.lerp(from, to + const Offset(40, 0), i / 10)!);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(session.pages, [b, c, a]);
    expect(session.current, c, reason: 'the current page stays current');

    // ← / → pick the page before / after; Ctrl moves the current one.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(session.current, a);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // Already first.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(session.pages, [a, b, c]);
    expect(session.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(session.index, 0);

    // A tap still selects.
    await s.tap(find.bySemanticsLabel('Page 2'));
    expect(session.current, b);
    await s.tap(find.byTooltip('Close'));
    await s.tap(find.text('Discard'));
    await tester.pumpAndSettle();
  }, variant: noCamera);

  testWidgets('cancelling the first pick leaves without creating anything', (tester) async {
    final services = await pumpLibrary(tester);
    ScanSources.debugSources = fakeSources();
    await scanFromLibrary(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ScanScreen), findsNothing);
    expect(services.notebooks.list(), isEmpty);
  }, variant: noCamera);

  testWidgets('a file that is no image is reported; closing a scan asks first', (tester) async {
    final services = await pumpLibrary(tester);
    ScanSources.debugSources = fakeSources(
      picks: [
        [
          photoFile('notes.png', Uint8List.fromList([1, 2, 3])),
          photoFile('page.png'),
        ],
      ],
    );
    await scanFromLibrary(tester);
    final s = scan(tester);
    await s.untilPages(1);
    expect(find.text('Couldn’t open “notes.png” as an image'), findsWidgets);

    await s.tap(find.byTooltip('Close'));
    expect(find.text('Discard this scan?'), findsOneWidget);
    await s.tap(find.text('Cancel'));
    expect(find.byType(ScanScreen), findsOneWidget);
    // Escape asks too.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Discard this scan?'), findsOneWidget);
    await s.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanScreen), findsNothing);
    expect(services.notebooks.list(), isEmpty);
  }, variant: noCamera);

  testWidgets('Insert ⊕ scans with the camera and more photos into the open notebook, undoably', (
    tester,
  ) async {
    final services = await pumpLibrary(tester);
    final notebook = services.notebooks.create(
      title: 'Lecture',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    final first = services.pages.pagesOf(notebook.id).single;
    await openFromLibrary(tester, notebook);
    ScanSources.debugSources = fakeSources(
      camera: [photoFile('shot1.jpg'), photoFile('retake.jpg')],
      picks: [
        [photoFile('a.png'), photoFile('b.png')],
      ],
    );
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan document…'));
    await tester.pumpAndSettle();
    // With a camera, the screen starts by offering both.
    expect(find.text('Choose photos…'), findsOneWidget);
    final s = scan(tester);
    await s.tap(find.text('Take photo'));
    await s.untilPages(1);

    await s.tap(find.byTooltip('Add page'));
    await s.tap(find.text('Choose photos…'));
    await s.untilPages(3);
    expect(find.text('3 pages'), findsOneWidget);
    // The + is a page-sized outline on the thumbnails' line, as tall as
    // they are (ScanPageStrip.thumbHeight).
    final add = tester.getRect(find.byTooltip('Add page'));
    final thumbs = find.descendant(of: find.byType(ScanPageStrip), matching: find.byType(RawImage));
    expect(thumbs, findsNWidgets(3));
    for (final e in thumbs.evaluate()) {
      final thumb = tester.getRect(find.byWidget(e.widget));
      expect(thumb.height, ScanPageStrip.thumbHeight);
      expect((thumb.top, thumb.bottom), (add.top, add.bottom));
    }

    // Retake page 3, then remove page 2.
    final session = tester.widget<ScanScreen>(find.byType(ScanScreen)).session;
    final before = session.current!.photo;
    await s.tap(find.text('Retake'));
    await pumpUntil(tester, () => session.current!.photo != before && session.display != null);
    expect(session.pages, hasLength(3));
    await s.tap(find.bySemanticsLabel('Page 2'));
    expect(session.index, 1);
    await s.tap(find.text('Remove'));
    await s.untilPages(2);

    await s.tap(find.text('Insert'));
    await pumpUntil(tester, () => services.pages.pagesOf(notebook.id).length == 3);
    await tester.pumpAndSettle();
    expect(find.byType(ScanScreen), findsNothing);
    final pages = services.pages.pagesOf(notebook.id);
    expect(pages.first.id, first.id);
    expect(pages.skip(1).every((p) => p.background?.kind == PageBackgroundKind.image), isTrue);

    // One undo takes the scanned pages out again.
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)').first);
    await tester.pumpAndSettle();
    expect(services.pages.pagesOf(notebook.id).map((p) => p.id), [first.id]);
  });

  testWidgets('corners drag (with a loupe), sides move both corners, folds are refused', (
    tester,
  ) async {
    var quad = Quad.bounds(400, 300).scaled(0.5).withCorner(0, const Offset(20, 20));
    final changes = <bool>[];
    tester.view
      ..physicalSize = const Size(448, 348)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => ScanCornerEditor(
            photo: null,
            photoSize: const Size(400, 300),
            quad: quad,
            onChanged: (q, {required done}) {
              changes.add(done);
              setState(() => quad = q);
            },
          ),
        ),
      ),
    );
    // margin 24 all round: photo pixels map 1:1 at an offset of 24.
    const origin = Offset(ScanCornerEditor.margin, ScanCornerEditor.margin);
    final gesture = await tester.startGesture(origin + const Offset(20, 20));
    await gesture.moveBy(const Offset(10, 6));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 6));
    await tester.pump();
    expect(quad.topLeft, const Offset(40, 32));
    // Past the opposite corner: refused, the corner stays.
    await gesture.moveTo(origin + const Offset(390, 290));
    await tester.pump();
    expect(quad.topLeft, const Offset(40, 32));
    await gesture.up();
    await tester.pump();
    expect(changes.last, isTrue);
    expect(changes.where((d) => d), hasLength(1));

    // The bottom side's middle moves both bottom corners.
    final bottom = (quad.bottomLeft + quad.bottomRight) / 2;
    final side = await tester.startGesture(origin + bottom);
    await side.moveBy(const Offset(0, 20));
    await tester.pump();
    await side.up();
    expect(quad.bottomLeft.dy, 170);
    expect(quad.bottomRight.dy, 170);

    // Corners stay on the photo.
    final corner = await tester.startGesture(origin + quad.topRight);
    await corner.moveBy(const Offset(500, -500));
    await tester.pump();
    await corner.up();
    expect(quad.topRight, const Offset(400, 0));
  });

  testWidgets('photos are kept no larger than the pages need', (tester) async {
    bool isJpeg(Uint8List b) => b[0] == 0xFF && b[1] == 0xD8;
    await tester.runAsync(() async {
      // Too big: re-encoded at the largest size used, the page found in it.
      final big = await ScanPhoto.load(deskPhoto(width: 600, height: 800), maxEdge: 400);
      expect((big.width, big.height), (300, 400));
      expect(isJpeg(big.bytes), isTrue);
      expect(big.detected!.topLeft.dx, closeTo(300 * 0.2, 4));
      expect(big.detected!.topLeft.dy, closeTo(400 * 0.12, 4));

      // Small but heavy (a noisy PNG): a JPEG of the same size.
      final rnd = math.Random(5);
      final noise = img.Image(width: 120, height: 90);
      for (final p in noise) {
        p.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
      }
      final png = img.encodePng(noise);
      final heavy = await ScanPhoto.load(png, maxEdge: 400);
      expect((heavy.width, heavy.height), (120, 90));
      expect(isJpeg(heavy.bytes), isTrue);
      expect(heavy.bytes.length, lessThan(png.length));

      // Small and light: kept as it is.
      final jpeg = img.encodeJpg(img.decodePng(deskPhoto(width: 240, height: 320))!);
      final kept = await ScanPhoto.load(jpeg, maxEdge: 400);
      expect(identical(kept.bytes, jpeg), isTrue);
    });
  });

  test('scanned pages are A4 or Letter when they are that shape, else A4-sized', () {
    final a4 = ScanImporter.pageSizeFor(2100, 2970);
    expect(a4.aspectRatio, closeTo(210 / 297, 0.001));
    final landscape = ScanImporter.pageSizeFor(2970, 2100);
    expect(landscape.width, a4.height);
    final letter = ScanImporter.pageSizeFor(850, 1100);
    expect(letter.aspectRatio, closeTo(8.5 / 11, 0.001));
    final square = ScanImporter.pageSizeFor(1000, 1000);
    expect(square.width, square.height);
    expect(square.width * square.height, closeTo(a4.width * a4.height, a4.width * 2));
  });
}
