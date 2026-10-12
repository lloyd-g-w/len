import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/audio/backends/audio_backends.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/ink/ink_surface.dart';
import 'package:len/ink/recognition/handwriting_recognizer.dart';

import 'screenshot_harness.dart';

// Helpers shared by the editor_surfaces*_screenshot_test.dart files.

const phone = Size(390, 844);
const tabletPortrait = Size(800, 1280);
const tablet = Size(1280, 800);
const desktop = Size(1440, 900);

/// A screen size: its name in file names, logical size, pixel ratio and
/// whether it has a phone's status / gesture bar insets.
typedef Screen = ({String name, Size size, double dpr, bool insets});

const Screen phoneScreen = (name: 'phone', size: phone, dpr: 2, insets: true);
const Screen tabletScreen = (name: 'tablet', size: tablet, dpr: 1, insets: false);
const Screen portraitScreen = (
  name: 'tablet_portrait',
  size: tabletPortrait,
  dpr: 1,
  insets: false,
);
const Screen desktopScreen = (name: 'desktop', size: desktop, dpr: 1, insets: false);

const modes = [ThemeMode.light, ThemeMode.dark];

/// A clock that stands still unless moved, for recordings' timers.
class StillClock extends Clock {
  int now = DateTime(2026, 10, 10, 9, 30).millisecondsSinceEpoch;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'x${_ids++}';
}

/// How [ShotRecognizer] answers.
enum Reading { text, slow, fails, empty }

/// A recogniser reading [lines] (one per recognised line, in order), or
/// behaving as [reading] says; [downloaded] / [download] fake the model.
class ShotRecognizer extends HandwritingRecognizer {
  ShotRecognizer({
    this.reading = Reading.text,
    this.downloaded = true,
    this.download = Reading.text,
    this.lines = const [
      ['Newton’s second law: F = ma', 'Newton’s second law: F = mo', 'newtons second law F=ma'],
    ],
  });

  final Reading reading, download;
  final List<List<String>> lines;
  bool downloaded;
  int _line = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> isModelDownloaded(String language) async => downloaded;

  @override
  Future<void> downloadModel(String language, {required bool wifiOnly}) {
    if (download == Reading.slow) return Completer<void>().future;
    if (download == Reading.fails) return Future.error(StateError('offline'));
    downloaded = true;
    return Future.value();
  }

  @override
  Future<List<RecognitionCandidate>> recognize(
    List<Stroke> strokes, {
    required String language,
    Size? writingArea,
    String preContext = '',
  }) {
    switch (reading) {
      case Reading.slow:
        return Completer<List<RecognitionCandidate>>().future;
      case Reading.fails:
        // Late, like a real recogniser: an immediate failure is reported as
        // unhandled before the dialog listens (see the report).
        return Future.delayed(
          const Duration(milliseconds: 100),
          () => throw StateError('recogniser crashed'),
        );
      case Reading.empty:
        return Future.value(const []);
      case Reading.text:
        final texts = lines[_line++ % lines.length];
        return Future.value([
          for (final (i, t) in texts.indexed) RecognitionCandidate(t, score: 1.0 - i / 10),
        ]);
    }
  }
}

/// In-memory services with no background recognition, optionally with
/// [recognizer] and [audio].
AppServices bareServices({Clock? clock, HandwritingRecognizer? recognizer, AudioBackends? audio}) {
  final db = AppDatabase.inMemory();
  SettingsRepository(db).handwritingIndexing = false;
  return AppServices.create(
    db,
    clock: clock ?? ShotClock('b'),
    recognizer: recognizer,
    audio: audio,
  );
}

/// [lines] of pseudo-handwriting starting at [origin] (world or page
/// coordinates), [width] wide, one stroke per word.
List<Stroke> inkLines(
  String surface,
  Offset origin, {
  int lines = 3,
  double width = 300,
  int seed = 1,
  double lineHeight = 56,
  int color = 0xFF1F2937,
  String prefix = 'w',
}) {
  final rnd = math.Random(seed);
  final strokes = <Stroke>[];
  for (var line = 0; line < lines; line++) {
    final y = origin.dy + line * lineHeight;
    var x = origin.dx;
    final end = origin.dx + width - rnd.nextDouble() * width * 0.2;
    while (x < end) {
      final wordWidth = 26 + rnd.nextDouble() * 60;
      final points = <StrokePoint>[];
      for (var t = 0.0; t <= wordWidth; t += 2.5) {
        final wiggle = math.sin(t / 4 + rnd.nextDouble()) * 8 + math.cos(t / 7) * 3;
        points.add(StrokePoint(x + t, y + wiggle, 0.4 + 0.3 * math.sin(t / 9).abs()));
      }
      strokes.add(
        Stroke(
          id: '$prefix$seed-${strokes.length}',
          surfaceId: surface,
          tool: InkTool.ballpoint,
          color: color,
          width: 2.6,
          points: points,
          createdAt: strokes.length + 1,
        ),
      );
      x += wordWidth + 14;
    }
  }
  return strokes;
}

/// A text box element.
SurfaceElement textElement(
  String id,
  String surface,
  String text,
  Offset at, {
  double width = 420,
  double size = 24,
}) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'text',
  rect: Rect.fromLTWH(at.dx, at.dy, width, size * 1.6),
  z: 1,
  createdAt: 1,
  data: {'text': text, 'size': size},
);

/// A canvas notebook "Whiteboard" with three lines of writing around the
/// world origin and a heading line.
Notebook whiteboard(AppServices s) {
  final n = s.notebooks.create(
    title: 'Whiteboard',
    kind: NotebookKind.canvas,
    paper: PaperStyle.dotted,
    coverColor: 0xFF0B7285,
  );
  s.strokes.save([
    ...inkLines(n.id, const Offset(-150, -90), lines: 1, color: 0xFF1C4ED8, prefix: 'h'),
    ...inkLines(n.id, const Offset(-150, -10), seed: 3),
  ]);
  return n;
}

/// Opens [notebook] of [services] in the editor workspace.
Future<void> pumpNotebook(
  WidgetTester tester,
  AppServices services,
  Notebook notebook, {
  required Screen screen,
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) async {
  setWindow(tester, screen.size, dpr: screen.dpr);
  if (screen.insets) {
    tester.view.padding = FakeViewPadding(top: 28 * screen.dpr, bottom: 20 * screen.dpr);
    addTearDown(tester.view.resetPadding);
  }
  addTearDown(services.dispose);
  // Unmount the editor (which saves settings) before the database closes.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  services.openNotebooks.open(notebook);
  await pumpApp(tester, services, const EditorWorkspace(), mode: mode, textScale: textScale);
}

/// The screen position of canvas [world] coordinates.
Offset canvasToScreen(WidgetTester tester, Offset world) {
  final surface = find.descendant(of: find.byType(CanvasView), matching: find.byType(InkSurface));
  final viewport = tester.widget<InkSurface>(surface.first).viewport;
  return tester.getTopLeft(surface.first) + viewport.toScreen(world);
}

/// Drags the mouse through [points].
Future<void> mouseDrag(WidgetTester tester, List<Offset> points) async {
  final gesture = await tester.startGesture(points.first, kind: PointerDeviceKind.mouse);
  for (final p in points.skip(1)) {
    await gesture.moveTo(p);
  }
  await gesture.up();
  await tester.pump();
}

/// Lassoes the canvas world rectangle [world] with the lasso tool (L).
Future<void> lassoCanvas(WidgetTester tester, Rect world) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
  await tester.pump();
  final corners = [
    world.topLeft,
    world.topRight,
    world.bottomRight,
    world.bottomLeft,
    world.topLeft + const Offset(0, 4),
  ];
  final screen = [for (final c in corners) canvasToScreen(tester, c)];
  final gesture = await tester.startGesture(screen.first, kind: PointerDeviceKind.mouse);
  for (var i = 1; i < screen.length; i++) {
    for (var k = 1; k <= 6; k++) {
      await gesture.moveTo(Offset.lerp(screen[i - 1], screen[i], k / 6)!);
    }
  }
  await gesture.up();
  await settle(tester);
}

/// Taps at [at] to close menus.
Future<void> dismiss(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await settle(tester);
}

/// Runs [body], printing layout overflows (`OVERFLOW …`) instead of failing
/// the test, so every screenshot still gets written; other errors fail it.
Future<void> guardOverflows(String name, Future<void> Function() body) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      // ignore: avoid_print
      print('OVERFLOW $name: ${text.split('\n').first}');
    } else {
      previous?.call(details);
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
}
