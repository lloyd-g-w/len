@Tags(['perf'])
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_chrome.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_handles.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

import '../shape_geometry_test.dart' show shapeStroke;
import 'support/big_library.dart';

/// Shapes and curves at scale: hold to snap at the end of a long stroke
/// (the recognisers and the curve fit run on the UI thread when the hold
/// is up), and what a pointer move over a selected curve with many
/// anchors costs (handle hit test, hover cursor, a handle dragged) on a
/// page of many shapes.
///
/// Run: `tool/heavy.sh nix develop .. -c flutter test test/perf/shapes_perf_test.dart`.
void main() {
  test('hold to snap at the end of a long stroke', () {
    final lines = <String>[];
    for (final n in [2000, 5000, 10000]) {
      final kinds = {
        'arc (a curve)': _stroke(
          n,
          (t) => Offset(400 * math.cos(t * 2.5), 300 * math.sin(t * 2.5)),
        ),
        'loop (an ellipse)': _stroke(
          n,
          (t) => Offset(300 * math.cos(t * 2 * math.pi), 200 * math.sin(t * 2 * math.pi)),
        ),
        'line': _stroke(n, (t) => Offset(800 * t, 3 * math.sin(t * 40))),
        'writing (nothing)': _stroke(
          n,
          (t) => Offset(2000 * t + 15 * math.sin(t * 900), 20 * math.cos(t * 1300)),
        ),
      };
      final times = [
        for (final MapEntry(key: name, value: points) in kinds.entries)
          () {
            late ShapeGeometry? shape;
            final us = bestUs(() => shape = HoldToStraighten.snapOf(points, 1), runs: 5);
            return '$name ${_ms(us)} → ${shape?.kind.name ?? 'none'}';
          }(),
      ];
      lines.add('$n points: ${times.join(', ')}');
    }
    report('SHAPES hold to snap (best of 5):\n  ${lines.join('\n  ')}');
  });

  for (final anchors in [20, ShapeGeometry.maxAnchors]) {
    for (final corners in [false, true]) {
      final kind = corners ? 'corner' : 'smooth';
      test('pointer over a curve of $anchors $kind anchors among 2,000 shapes', () {
        final db = AppDatabase.inMemory();
        final repository = StrokeRepository(db, deviceId: 'd');
        final model = SurfaceModel(surfaceId: 's', repository: repository);
        final curve = _curve(anchors, corners: corners);
        repository.save([
          for (var i = 0; i < 2000; i++)
            _on(
              shapeStroke(
                ShapeBuilder.dragged(
                  ShapeKind.values[i % 5 + 2],
                  Offset(i % 50 * 30.0, i ~/ 50 * 30.0),
                  Offset(i % 50 * 30.0 + 24, i ~/ 50 * 30.0 + 20),
                ),
                id: 'shape$i',
              ),
            ),
          _on(shapeStroke(curve, id: 'curve')),
        ]);
        model.ensureLoaded(const Rect.fromLTWH(-1000, -1000, 4000, 3000));
        final viewport = ViewportController()..setSize(const Size(1280, 800));
        final content = ContentTools(
          model: model,
          viewport: viewport,
          tools: ToolSettings(stylusOnly: false)..tool = EditorTool.lasso,
          live: LiveInk(),
          clipboard: InkClipboard(),
        );
        final selection = content.selection..select([model.strokeById('curve')!], const []);
        final shape = selection.shape!;
        final frame = selection.frame!;
        // Moves along the curve's middle, over handles and between them.
        final path = [for (var i = 0; i < 50; i++) Offset(100 + i * 21.3, 400 + (i % 5) * 7.0)];
        int each(void Function(Offset p) f) =>
            bestUs(() => path.forEach(f), runs: 5) ~/ path.length;

        final hit = each(
          (p) => SelectionChrome.shapeHandleAt(
            shape,
            viewport,
            p,
            frame: frame,
            kind: PointerDeviceKind.mouse,
          ),
        );
        final placed = each((_) => SelectionChrome.shapeHandles(shape, viewport));
        final hover = each((p) => content.cursorAt(EditorTool.lasso, p));
        final tap = each(content.holds);
        // A handle dragged: the curve rebuilt and recorded per move.
        var i = 0;
        final drag = each((p) {
          i++;
          selection.reshape(ShapeHandles.drag(shape, 3 * (anchors ~/ 2), p));
        });
        selection.cancelReshape();
        report(
          'SHAPES curve, $anchors $kind anchors (${shape.points.length} points): '
          'handle hit ${_ms(hit)}, handles placed ${_ms(placed)}, '
          'hover cursor ${_ms(hover)}, press test ${_ms(tap)}, '
          'anchor dragged ${_ms(drag)} a move ($i)',
        );
        content.dispose();
        model.dispose();
        db.close();
      });
    }
  }
}

/// A stroke of [n] points along [at] (t from 0 to 1), pressure 0.5.
List<StrokePoint> _stroke(int n, Offset Function(double t) at) => [
  for (var i = 0; i < n; i++)
    () {
      final p = at(i / (n - 1)) + const Offset(500, 400);
      return StrokePoint(p.dx, p.dy, 0.5);
    }(),
];

/// An open curve of [anchors] anchors waving across (100, 400)–(1180,
/// 400): smooth (tangents a third of the way to the next) or [corners]
/// (no tangents, as taps place them).
ShapeGeometry _curve(int anchors, {required bool corners}) {
  final step = 1080 / (anchors - 1);
  final a = [
    for (var i = 0; i < anchors; i++) Offset(100 + i * step, 400 + 30 * math.sin(i * 0.7)),
  ];
  return ShapeGeometry(ShapeKind.curve, [
    for (var i = 0; i < anchors; i++) ...[
      if (i > 0) corners ? a[i] : a[i] - (a[i] - a[i - 1]) / 3,
      a[i],
      if (i < anchors - 1) corners ? a[i] : a[i] + (a[i + 1] - a[i]) / 3,
    ],
  ]);
}

Stroke _on(Stroke s) => Stroke(
  id: s.id,
  surfaceId: 's',
  tool: s.tool,
  color: s.color,
  width: s.width,
  points: s.points,
  createdAt: s.createdAt,
  style: s.style,
  shape: s.shape,
);

String _ms(int us) => '${(us / 1000).toStringAsFixed(3)} ms';
