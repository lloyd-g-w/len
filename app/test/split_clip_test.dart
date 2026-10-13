import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_canvas.dart';

import 'split_view_test.dart';

/// The colour of the pixel at [at] (logical = physical here).
Future<Color> pixelAt(WidgetTester tester, Offset at) async {
  final image = await tester.runAsync(() async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    return layer.toImage(Offset.zero & tester.view.physicalSize);
  });
  final data = (await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final i = (at.dy.round() * image!.width + at.dx.round()) * 4;
  final c = Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
  image.dispose();
  return c;
}

/// A thick red band across a page, 100 units below its top.
Stroke redBand(String surface) => Stroke(
  id: 'band',
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFFFF0000,
  width: 60,
  points: [for (var x = 0.0; x <= 800; x += 20) StrokePoint(x, 400, 1)],
  createdAt: 1,
);

void main() {
  testWidgets('a pane zoomed in stays inside its half of the split', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    // Dark pages on the left, so anything of it drawn on the right shows,
    // and thick red ink across the page.
    s.pages.setPaper([for (final p in s.pages.pagesOf(physics.id)) p.id], color: PaperColor.dark);
    s.strokes.save([redBand(s.pages.pagesOf(physics.id).first.id)]);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    // Ink right at the left page's right edge.
    final session = tester.widgetList<EditorCanvas>(find.byType(EditorCanvas)).first.session;
    session.commands!.reload();
    await tester.pumpAndSettle();
    final left = tester.getRect(paneOf(0));
    final right = tester.getRect(paneOf(1));
    // Zoom the left pane far in about the band's right end.
    final frame = session.doc!.layout.frameOf(0)!;
    final focal = session.doc!.viewport.toScreen(frame.topLeft + Offset(frame.width - 10, 400));
    // Just inside the other pane, on the band's line.
    final probe = Offset(right.left + 3, left.top + focal.dy);
    final before = await pixelAt(tester, probe);
    session.doc!.viewport.zoomAt(focal, 6);
    await tester.pumpAndSettle();
    expect(tester.getRect(paneOf(0)), left);
    final after = await pixelAt(tester, probe);
    expect(after, before, reason: 'the left pane drew over the right one');
  });

  testWidgets('the right pane zoomed in stays out of the left one', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    s.pages.setPaper([for (final p in s.pages.pagesOf(chemistry.id)) p.id], color: PaperColor.dark);
    s.strokes.save([redBand(s.pages.pagesOf(chemistry.id).first.id)]);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    final session = tester.widgetList<EditorCanvas>(find.byType(EditorCanvas)).last.session;
    session.commands!.reload();
    await tester.pumpAndSettle();
    final left = tester.getRect(paneOf(0));
    final right = tester.getRect(paneOf(1));
    final frame = session.doc!.layout.frameOf(0)!;
    final focal = session.doc!.viewport.toScreen(frame.topLeft + const Offset(10, 400));
    final probe = Offset(left.right - 3, right.top + focal.dy);
    final before = await pixelAt(tester, probe);
    session.doc!.viewport.zoomAt(focal, 6);
    await tester.pumpAndSettle();
    final after = await pixelAt(tester, probe);
    expect(after, before, reason: 'the right pane drew over the left one');
  });

  testWidgets('a zoomed canvas pane stays inside its half', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester, kind: NotebookKind.canvas);
    s.notebooks.update(s.notebooks.get(physics.id)!.copyWith(paperColor: PaperColor.dark));
    s.strokes.save([redBand(physics.id)]);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    final panes = find.byType(EditorCanvas);
    final left = tester.getRect(panes.first);
    final right = tester.getRect(panes.last);
    final session = tester.widgetList<EditorCanvas>(panes).first.session;
    final nav = session.canvasNav!;
    final focal = nav.viewport.toScreen(const Offset(790, 400));
    // Just inside the other pane, on the band's line.
    final probe = Offset(right.left + 3, left.top + focal.dy);
    final before = await pixelAt(tester, probe);
    nav.viewport.zoomAt(focal, 8);
    await tester.pumpAndSettle();
    final after = await pixelAt(tester, probe);
    debugPrint(
      'PIX3 left=${await pixelAt(tester, Offset(left.right - 20, left.top + focal.dy))} before=$before after=$after',
    );
    expect(after, before, reason: 'the canvas drew over the other pane');
  });
}
