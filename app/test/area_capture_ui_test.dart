import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/capture/capture_actions.dart';
import 'package:len/features/editor/capture/capture_layer.dart';
import 'package:len/features/editor/capture/capture_result_bar.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/toolbar/insert_menu.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

import 'canvas_export_test.dart' show pixel, pngSize;
import 'support/real_async.dart';
import 'support/selection_actions.dart';
import 'support/tester_clock.dart';

const _red = 0xFFE03131;

/// A red line across the surface at y = 200, from x = 100 to 300.
Stroke _ink(String surface) => Stroke(
  id: 'ink',
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: _red,
  width: 8,
  points: [for (var x = 100.0; x <= 300; x += 10) StrokePoint(x, 200, 0.5)],
  createdAt: 1,
);

/// What the app wrote to the system clipboard.
class _Clipboard {
  _Clipboard() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (call) async {
      switch (call.method) {
        case 'write':
          final png = (call.arguments as Map<Object?, Object?>)['png'] as Uint8List?;
          if (png != null) images.add(png);
          return true;
        case 'files' || 'peek':
          return const <Object>[];
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        (call) async => const {'files', 'peek'}.contains(call.method) ? const <Object>[] : null,
      ),
    );
  }

  final images = <Uint8List>[];
}

/// Opens an editor of a one-page notebook of grid paper (or a [canvas])
/// with [_ink]; returns the services, the surface's id and how to put a
/// surface point on screen.
Future<(AppServices, String, Offset Function(Offset))> _open(
  WidgetTester tester, {
  bool canvas = false,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory(), clock: const TesterClock());
  addTearDown(services.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  final nb = services.notebooks.create(
    title: 'Capture',
    kind: canvas ? NotebookKind.canvas : NotebookKind.paged,
    paper: PaperStyle.gridLarge,
    coverColor: 0,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.gridLarge)),
  );
  final surface = canvas ? nb.id : services.pages.pagesOf(nb.id).single.id;
  services.strokes.save([_ink(surface)]);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  Offset toScreen(Offset p) {
    if (canvas) {
      return tester.widget<CanvasView>(find.byType(CanvasView)).navigation.viewport.toScreen(p);
    }
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    return doc.viewport.toScreen(p + doc.layout.frameOf(0)!.topLeft);
  }

  return (services, surface, toScreen);
}

Finder get _hint => find.text(CaptureLayer.hint);
Finder get _bar => find.byKey(const ValueKey('capture-result'));

Future<void> _startCapture(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Insert'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(InsertActions.captureLabel));
  await tester.pumpAndSettle();
}

/// Drags the mouse from [from] to [to] (screen) and waits for the capture.
Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= 4; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 4)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) => pumpUntil(
  tester,
  () => find.text(CaptureResultBar.copying).evaluate().isEmpty,
  reason: 'the capture',
);

/// The red ink at [at] (a fraction of the PNG's size) is there.
Future<void> _expectInk(Uint8List png, Offset at) async {
  final (w, h) = pngSize(png);
  final c = await pixel(png, (at.dx * w).round(), (at.dy * h).round());
  expect((c.r * 255).round(), greaterThan(180), reason: 'red ink, got $c');
  expect((c.g * 255).round(), lessThan(120), reason: 'red ink, got $c');
}

void main() {
  testWidgets('Insert ⊕ → Capture area: a drag copies what is there, ink and grid, as a PNG; '
      'Insert as image adds it, undoably', (tester) async {
    final clipboard = _Clipboard();
    final (services, page, toScreen) = await _open(tester);
    await _startCapture(tester);
    expect(_hint, findsOneWidget);

    // From (50, 150) to (350, 250) on the page: the ink runs across its middle.
    await tester.runAsync(() async {});
    await _drag(tester, toScreen(const Offset(50, 150)), toScreen(const Offset(350, 250)));
    expect(find.text(CaptureResultBar.copied), findsOneWidget);
    expect(_hint, findsNothing);
    expect(clipboard.images, hasLength(1));
    final png = clipboard.images.single;
    final (w, h) = pngSize(png);
    expect(w / h, closeTo(3, 0.05), reason: '300 × 100 units');
    expect(w, greaterThanOrEqualTo(900), reason: 'at least 288 dpi');
    await tester.runAsync(() => _expectInk(png, const Offset(0.5, 0.5)));
    // Paper (opaque) above the ink.
    final paper = (await tester.runAsync(() => pixel(png, 3, 3)))!;
    expect(paper.a, 1);

    await tester.tap(find.byTooltip(CaptureResultBar.insertLabel));
    await pumpUntil(
      tester,
      () => services.elements.allOn(page).isNotEmpty,
      reason: 'the image inserted',
    );
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
    final image = services.elements.allOn(page).single;
    expect(image.knownType, ElementType.image);
    expect(image.rect.width / image.rect.height, closeTo(3, 0.05));
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pumpAndSettle();
    expect(services.elements.allOn(page), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a canvas too; Done closes the bar and leaves the canvas as it was', (
    tester,
  ) async {
    final clipboard = _Clipboard();
    final (services, surface, toScreen) = await _open(tester, canvas: true);
    await _startCapture(tester);
    await _drag(tester, toScreen(const Offset(150, 180)), toScreen(const Offset(250, 220)));
    expect(find.text(CaptureResultBar.copied), findsOneWidget);
    await tester.runAsync(() => _expectInk(clipboard.images.single, const Offset(0.5, 0.5)));
    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
    expect(services.elements.allOn(surface), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape, or a press on the chrome, cancels; a click is no area', (tester) async {
    final clipboard = _Clipboard();
    final (_, _, toScreen) = await _open(tester);
    await _startCapture(tester);
    await tester.tapAt(toScreen(const Offset(200, 200)), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(_hint, findsOneWidget, reason: 'still waiting for a drag');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_hint, findsNothing);
    // The editor's shortcuts work again.
    final tools = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session.tools;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(tools.tool, EditorTool.highlighter);

    await _startCapture(tester);
    await tester.tap(find.byTooltip('Insert'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_hint, findsNothing);
    expect(clipboard.images, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the selection menu copies the selection as an image, background and all', (
    tester,
  ) async {
    final clipboard = _Clipboard();
    final (_, _, _) = await _open(tester);
    final session = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;
    final selection = session.content.selection;
    selection.select(selection.model.strokesNear(const Rect.fromLTWH(0, 0, 1000, 1000)), const []);
    await tester.pumpAndSettle();
    expect(await selectionOffers(tester, copyAsImageLabel), isTrue);
    await selectionAction(tester, copyAsImageLabel);
    await _settle(tester);
    expect(find.text(CaptureResultBar.copied), findsOneWidget);
    final png = clipboard.images.single;
    final (w, h) = pngSize(png);
    // The ink's box (200 × 8 units) and the frame's room around it.
    expect(w / h, greaterThan(6), reason: '$w × $h');
    await tester.runAsync(() => _expectInk(png, const Offset(0.5, 0.5)));
    // Grid paper behind it, opaque (a lasso Copy's picture is transparent).
    final corner = (await tester.runAsync(() => pixel(png, 0, 0)))!;
    expect(corner.a, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
