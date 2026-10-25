import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/shapes/shape_builder.dart';

import 'content_tools_ui_test.dart' show key, liveStrokes, mouseDrag, openCanvas;

/// Handwriting-like loops ("llll") with natural pressure swell, sampled
/// like a stylus (~1.5 units apart).
List<StrokePoint> loops(Offset origin, {double scale = 1}) {
  final pts = <StrokePoint>[];
  for (var t = 0.0; t <= 4 * 2 * math.pi; t += 0.06) {
    final x = 9 * t - 14 * math.sin(t);
    final y = -22 * math.cos(t) + 10;
    final p = 0.35 + 0.55 * math.pow(math.sin(t / 2).abs(), 1.5);
    pts.add(StrokePoint(origin.dx + x * scale, origin.dy + y * scale, p.toDouble()));
  }
  return pts;
}

/// Loads Roboto and the Material icons from the Flutter SDK, so goldens
/// show real text and icons instead of placeholder boxes.
Future<void> loadFonts() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = '${artifacts.path}/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const roboto = [
    'Roboto-Regular.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
    'Roboto-BoldItalic.ttf',
    'Roboto-Medium.ttf',
  ];
  await load('Roboto', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Stroke shape(String id, ShapeKind kind, Offset a, Offset b, int color, {int? fill}) {
  final config = PenConfig.defaultsFor(InkTool.ballpoint);
  final geometry = ShapeBuilder.dragged(kind, a, b);
  return Stroke(
    id: id,
    surfaceId: '',
    tool: InkTool.ballpoint,
    color: color,
    width: 3,
    points: ShapeBuilder.pointsOf(geometry),
    createdAt: 2,
    style: ShapeBuilder.styleFor(config.styleFor(InkTool.ballpoint)).withFill(fill),
    shape: geometry,
  );
}

SurfaceElement text(String surface, Offset at, TextData data, {double width = 260}) =>
    SurfaceElement(
      id: 'text-${at.dx}-${at.dy}',
      surfaceId: surface,
      type: 'text',
      rect: Rect.fromLTWH(at.dx, at.dy, width, TextLayout.heightOf(data, width)),
      z: 1,
      createdAt: 3,
      data: data.toJson(),
    );

Future<(AppServices, Notebook)> seededCanvas(WidgetTester tester) async {
  await loadFonts();
  return openCanvas(
    tester,
    seed: (s, nb) {
      Stroke on(Stroke st) => Stroke(
        id: st.id,
        surfaceId: nb.id,
        tool: st.tool,
        color: st.color,
        width: st.width,
        points: st.points,
        createdAt: st.createdAt,
        style: st.style,
        shape: st.shape,
      );
      s.strokes.save([
        on(
          Stroke(
            id: 'loops',
            surfaceId: nb.id,
            tool: InkTool.ballpoint,
            color: 0xFF1F2937,
            width: 2.5,
            points: loops(const Offset(120, 520), scale: 1.2),
            createdAt: 1,
          ),
        ),
        on(
          shape(
            'rect',
            ShapeKind.rectangle,
            const Offset(140, 180),
            const Offset(360, 320),
            0xFF1C7ED6,
            // A tint of its ink.
            fill: 0x401C7ED6,
          ),
        ),
        on(
          shape(
            'ellipse',
            ShapeKind.ellipse,
            const Offset(420, 180),
            const Offset(620, 320),
            0xFFE03131,
            fill: 0x1FE03131,
          ),
        ),
        on(
          shape(
            'arrow',
            ShapeKind.arrow,
            const Offset(680, 300),
            const Offset(860, 190),
            0xFF2F9E44,
          ),
        ),
        on(
          shape(
            'star',
            ShapeKind.star,
            const Offset(920, 170),
            const Offset(1080, 320),
            0xFFF59F00,
            // Solid.
            fill: 0xFFFACC15,
          ),
        ),
        on(
          shape(
            'tri',
            ShapeKind.triangle,
            const Offset(700, 420),
            const Offset(860, 560),
            0xFF7048E8,
          ),
        ),
        on(
          shape(
            'diamond',
            ShapeKind.diamond,
            const Offset(920, 420),
            const Offset(1060, 560),
            0xFF0CA678,
          ),
        ),
      ]);
      s.elements.save([
        text(
          nb.id,
          const Offset(420, 420),
          TextData.rich(
            text: 'Meeting notes\nShapes, lasso & text',
            paras: const [ParaStyle(heading: 2)],
            spans: const [StyledRange(14, 20, SpanStyle(underline: true))],
          ),
        ),
        text(
          nb.id,
          const Offset(420, 540),
          TextData.rich(
            text: 'Centred italic text wraps inside its box.',
            spans: const [StyledRange(0, 41, SpanStyle(italic: true))],
            font: TextFont.lora,
            fontSize: 18,
            align: TextAlignment.center,
            color: 0xFFC2255C,
          ),
          width: 220,
        ),
      ]);
    },
  );
}

void main() {
  testWidgets('content: shapes, text and a lasso selection', (tester) async {
    await seededCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [
      Offset(400, 160),
      Offset(640, 160),
      Offset(660, 400),
      Offset(660, 620),
      Offset(400, 620),
      Offset(390, 300),
      Offset(400, 165),
    ]);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_selection.png'),
    );
  });

  testWidgets('content: a lasso while it is drawn (no fill, ink beneath untouched)', (
    tester,
  ) async {
    await seededCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    // A hand-drawn loop around the ellipse and the text, not yet closed.
    final gesture = await tester.startGesture(
      const Offset(530, 140),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 60; i++) {
      final t = i / 64 * 2 * math.pi;
      await gesture.moveTo(
        Offset(530 + 160 * math.sin(t) + 3 * math.sin(7 * t), 380 - 240 * math.cos(t)),
      );
    }
    await tester.pump();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_lasso_live.png'),
    );
    await gesture.up();
  });

  testWidgets('content: rotating a selection previews the transform', (tester) async {
    await seededCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [
      Offset(120, 150),
      Offset(380, 150),
      Offset(380, 340),
      Offset(120, 340),
      Offset(120, 155),
    ]);
    // Grab the rotate handle (above the top edge) and turn it.
    final gesture = await tester.startGesture(
      const Offset(250, 130),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(const Offset(300, 135));
    await gesture.moveTo(const Offset(380, 170));
    await tester.pump();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_rotate.png'),
    );
    await gesture.up();
  });

  testWidgets('content: editing a text box', (tester) async {
    await seededCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(500, 440)]);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_text_edit.png'),
    );
  });

  testWidgets('content: a filled shape while it is drawn, over earlier ink', (tester) async {
    final (services, notebook) = await seededCanvas(tester);
    // The first tap selects the tool, the second opens its options.
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shape-ellipse')));
    await tester.tap(find.byTooltip('Medium tint'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      const Offset(100, 470),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(const Offset(250, 520));
    await gesture.moveTo(const Offset(420, 590));
    await tester.pump();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_fill_live.png'),
    );
    await gesture.up();
    await tester.pump();
    final drawn = liveStrokes(services, notebook.id).where((s) => s.style.fill != null);
    // The ellipse, with the seeded rectangle, ellipse and star.
    expect(drawn, hasLength(4));
  });

  testWidgets('content: a tap on a fill selects the shape; Style changes its fill', (tester) async {
    final (services, notebook) = await seededCanvas(tester);
    int? fillOf(String colour) => liveStrokes(
      services,
      notebook.id,
    ).singleWhere((s) => s.color == int.parse(colour)).style.fill;
    await key(tester, LogicalKeyboardKey.keyL);
    // Inside the tinted rectangle, far from its outline.
    await mouseDrag(tester, const [Offset(250, 250)]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Style'));
    await tester.pumpAndSettle();
    expect(find.text('Medium tint'), findsOneWidget);
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_fill_style.png'),
    );
    await tester.tap(find.byTooltip('Solid colour'));
    await tester.pumpAndSettle();
    expect(fillOf('0xFF1C7ED6'), 0xFF1C7ED6);
    expect(find.text('Fill colour'), findsOneWidget);
    await tester.tap(find.byTooltip('No fill'));
    await tester.pumpAndSettle();
    expect(fillOf('0xFF1C7ED6'), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(fillOf('0xFF1C7ED6'), 0xFF1C7ED6);
  });

  testWidgets('content: toolbar and shape picker on a phone', (tester) async {
    await loadFonts();
    await openCanvas(tester, size: const Size(390, 844));
    // Phones: the compact toolbar's switcher picks the tool and its settings.
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();
    // Tapping the active tool again opens its options.
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_phone_shapes.png'),
    );
  });
}
