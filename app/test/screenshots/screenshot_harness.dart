import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/ui/app_theme.dart';

/// Whether to write PNGs (`flutter test --dart-define=SCREENSHOTS=true`).
/// Without it the scenarios still render, as layout smoke tests.
const bool writeScreenshots = bool.fromEnvironment('SCREENSHOTS');

/// Loads Roboto and the Material icon font from the Flutter SDK so text
/// and icons render as real glyphs instead of test boxes.
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final roboto = FontLoader('Roboto');
  for (final w in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    final file = File('${dir.path}/Roboto-$w.ttf');
    if (file.existsSync()) roboto.addFont(_bytes(file));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(_bytes(File('${dir.path}/MaterialIcons-Regular.otf')));
  await icons.load();
}

Future<ByteData> _bytes(File f) async => ByteData.sublistView(await f.readAsBytes());

/// Sets the test window to [size] logical pixels at [dpr].
void setWindow(WidgetTester tester, Size size, {double dpr = 1}) {
  tester.view
    ..physicalSize = size * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

/// Pumps [home] with [services] in a real-looking app shell.
Future<void> pumpApp(
  WidgetTester tester,
  AppServices services,
  Widget home, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: home,
        ),
      ),
    ),
  );
  await settle(tester);
}

final shotKey = GlobalKey(debugLabel: 'screenshot');

/// Lets animations and queued thumbnail renders finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the library section or folder [label]: from the sidebar, or on
/// phones from the drawer.
Future<void> openLibrarySection(WidgetTester tester, String label) async {
  // (The drawer's button may have scrolled away with the header.)
  for (final scaffold in tester.stateList<ScaffoldState>(find.byType(Scaffold))) {
    if (scaffold.hasDrawer) {
      scaffold.openDrawer();
      await settle(tester);
      break;
    }
  }
  await tester.tap(find.text(label).first);
  await settle(tester);
}

/// Writes the current frame to `build/screenshots/<name>.png`, optionally
/// only the [crop] rectangle (logical pixels).
Future<void> shoot(WidgetTester tester, String name, {Rect? crop}) async {
  if (!writeScreenshots) return;
  // Draw real elevation shadows (flutter_test replaces them with outlines),
  // restoring the default before the test ends.
  await _repaintWithShadows(tester, true);
  await tester.runAsync(() async {
    final dpr = tester.view.devicePixelRatio;
    final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    var image = await boundary.toImage(pixelRatio: dpr);
    if (crop != null) image = await _crop(image, crop, dpr);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screenshots/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
  await _repaintWithShadows(tester, false);
}

Future<ui.Image> _crop(ui.Image image, Rect crop, double dpr) {
  final src = Rect.fromLTRB(crop.left * dpr, crop.top * dpr, crop.right * dpr, crop.bottom * dpr);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(image, src, Offset.zero & src.size, Paint());
  return recorder.endRecording().toImage(src.width.round(), src.height.round());
}

Future<void> _repaintWithShadows(WidgetTester tester, bool shadows) async {
  debugDisableShadows = !shadows;
  void markAll(RenderObject o) {
    o.markNeedsPaint();
    o.visitChildren(markAll);
  }

  for (final view in tester.binding.renderViews) {
    markAll(view);
  }
  await tester.pump();
}

/// A deterministic clock for stable "last edited" labels.
class ShotClock extends Clock {
  ShotClock([this.prefix = 'id']);

  /// Prefix of generated ids, so several clocks never collide.
  final String prefix;
  int now = DateTime(2026, 10, 10, 9, 30).millisecondsSinceEpoch;
  int _ids = 0;

  @override
  int nowMs() => now += 60000;

  @override
  String newId() => '$prefix${_ids++}';
}

/// Services with a realistic library: folders, notebooks with handwriting,
/// canvases, favourites and a trashed notebook.
AppServices seededServices() {
  final clock = ShotClock();
  final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  final school = s.folders.create(name: 'School', color: Palette.covers[0]);
  s.folders.create(name: 'Maths', parentId: school.id, color: Palette.covers[5]);
  final work = s.folders.create(name: 'Work', color: Palette.covers[1]);
  s.folders.create(name: 'Sketches', color: Palette.covers[2]);

  Notebook nb(
    String title,
    int color, {
    NotebookKind kind = NotebookKind.paged,
    PaperStyle paper = PaperStyle.wideRuled,
    String? folder,
    int ink = 0,
  }) {
    final n = s.notebooks.create(
      title: title,
      kind: kind,
      paper: paper,
      coverColor: Palette.covers[color],
      folderId: folder,
    );
    if (ink > 0) {
      final surface = kind == NotebookKind.canvas ? n.id : s.pages.pagesOf(n.id).first.id;
      s.strokes.save(handwriting(surface, clock, lines: ink, canvas: kind == NotebookKind.canvas));
    }
    return n;
  }

  nb('Physics — Mechanics', 0, ink: 9);
  final journal = nb('Journal 2026', 4);
  nb('Whiteboard', 8, kind: NotebookKind.canvas, paper: PaperStyle.dotted, ink: 5);
  nb('Meeting notes', 1, paper: PaperStyle.gridLarge, folder: work.id, ink: 6);
  nb('Recipes', 2);
  nb('Ideas', 5, ink: 4, paper: PaperStyle.dotted);
  nb('Spanish vocabulary', 7);
  nb('Travel plans', 9);
  final old = nb('Old drafts', 6);
  s.notebooks.setFavorite(journal.id, true);
  s.notebooks.trash(old.id);
  return s;
}

/// Wavy pseudo-handwriting: words along ruled lines.
List<Stroke> handwriting(String surface, Clock clock, {required int lines, required bool canvas}) {
  final rnd = math.Random(surface.hashCode);
  final strokes = <Stroke>[];
  for (var line = 0; line < lines; line++) {
    final y = (canvas ? -120 : 150) + line * 64.0;
    var x = canvas ? -260.0 : 110.0;
    final end = canvas ? 260.0 : 700.0 - rnd.nextDouble() * 200;
    while (x < end) {
      final wordWidth = 30 + rnd.nextDouble() * 70;
      final points = <StrokePoint>[];
      for (var t = 0.0; t <= wordWidth; t += 2.5) {
        final wiggle = math.sin(t / 4 + rnd.nextDouble()) * 9 + math.cos(t / 7) * 4;
        points.add(StrokePoint(x + t, y - 10 + wiggle, 0.4 + 0.3 * math.sin(t / 9).abs()));
      }
      strokes.add(
        Stroke(
          id: clock.newId(),
          surfaceId: surface,
          tool: InkTool.ballpoint,
          color: line == 0 ? 0xFF1C7ED6 : 0xFF1F2937,
          width: line == 0 ? 4 : 2.6,
          points: points,
          createdAt: strokes.length,
        ),
      );
      x += wordWidth + 16;
    }
  }
  if (!canvas) {
    strokes.add(
      Stroke(
        id: clock.newId(),
        surfaceId: surface,
        tool: InkTool.highlighter,
        color: 0xFFFACC15,
        width: 22,
        points: [for (var t = 0.0; t < 260; t += 10) StrokePoint(110 + t, 205, 0.5)],
        createdAt: 999,
      ),
    );
  } else {
    strokes.add(
      Stroke(
        id: clock.newId(),
        surfaceId: surface,
        tool: InkTool.ballpoint,
        color: 0xFFE03131,
        width: 5,
        points: [
          for (var a = 0.0; a < 6.4; a += 0.1)
            StrokePoint(120 + math.cos(a) * 90, 150 + math.sin(a) * 60, 0.6),
        ],
        createdAt: 1000,
      ),
    );
  }
  return strokes;
}

/// The library header's "Empty trash" (an icon button on phones).
/// The ⋯ of the first notebook card (folders have one too).
Finder firstCardMore() =>
    find.descendant(of: find.byType(NotebookCard), matching: find.byTooltip('More')).first;

Finder emptyTrashButton() {
  final icon = find.byTooltip('Empty trash…');
  return icon.evaluate().isNotEmpty ? icon : find.text('Empty trash…');
}

/// The library's "New" button: the grid's "New…" tile on wide screens, else
/// the floating button.
Finder newButton() {
  final tile = find.byKey(const ValueKey('new-notebook-tile'));
  return tile.evaluate().isNotEmpty ? tile : find.byTooltip('New notebook').last;
}

/// Opens the library's search field: on phones it hides behind 🔍.
Future<void> openSearch(WidgetTester tester) async {
  final button = find.byTooltip('Search');
  if (button.evaluate().isEmpty) return;
  await tester.tap(button);
  await settle(tester);
}
