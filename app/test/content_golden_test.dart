import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tool_switcher.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_kind.dart';

import 'content_tools_ui_test.dart' show key, mouseDrag, openCanvas;

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

Stroke shape(String id, ShapeKind kind, Offset a, Offset b, int color) {
  final config = PenConfig.defaultsFor(InkTool.ballpoint);
  return Stroke(
    id: id,
    surfaceId: '',
    tool: InkTool.ballpoint,
    color: color,
    width: 3,
    points: ShapeBuilder.points(ShapeBuilder.outline(kind, a, b)),
    createdAt: 2,
    style: ShapeBuilder.styleFor(config.styleFor(InkTool.ballpoint, 3)),
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

Future<void> seededCanvas(WidgetTester tester) async {
  await loadFonts();
  await openCanvas(
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
          ),
        ),
        on(
          shape(
            'ellipse',
            ShapeKind.ellipse,
            const Offset(420, 180),
            const Offset(620, 320),
            0xFFE03131,
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

  testWidgets('content: toolbar and shape picker on a phone', (tester) async {
    await loadFonts();
    await openCanvas(tester, size: const Size(390, 844));
    // Phones: the compact toolbar's switcher picks the tool and its settings.
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shapes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shapes settings'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_phone_shapes.png'),
    );
  });
}
