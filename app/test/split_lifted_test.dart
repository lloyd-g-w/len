import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/ink/undo_history.dart';

import 'split_clip_test.dart' show pixelAt;
import 'split_view_test.dart';

/// A thick red band across the canvas at y = 300.
Stroke band(String surface) => Stroke(
  id: 'band',
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFFFF0000,
  width: 40,
  points: [for (var x = 40.0; x <= 400; x += 20) StrokePoint(x, 300, 1)],
  createdAt: 1,
);

bool reddish(Color c) => c.r > 0.8 && c.g < 0.3 && c.b < 0.3;

void main() {
  testWidgets('a selection in one view still shows (and moves) in the other view', (tester) async {
    final (s, physics, _) = await pumpWorkspace(tester, kind: NotebookKind.canvas);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final [left, right] = tester.widgetList<EditorCanvas>(find.byType(EditorCanvas)).toList();
    final model = left.session.canvas!..addStroke(band(physics.id));
    await tester.pumpAndSettle();
    final rightBox = tester.getRect(find.byType(EditorCanvas).last);
    // Where the band shows in the right view.
    Offset inRight(Offset world) => rightBox.topLeft + right.session.viewport.toScreen(world);
    expect(reddish(await pixelAt(tester, inRight(const Offset(200, 300)))), isTrue);

    // Selected in the left view: lifted out of the surface…
    final selection = left.session.content.selection;
    selection.select(model.strokesNear(const Rect.fromLTWH(0, 0, 500, 500)), const []);
    await tester.pump();
    expect(model.isHidden('band'), isTrue);
    // …but still drawn in the right view.
    expect(reddish(await pixelAt(tester, inRight(const Offset(200, 300)))), isTrue);

    // Dragged (the gesture in progress): the right view follows.
    final move = selection.frame!.moved(const Offset(0, 100));
    selection.setPreview(move.transform, move.frame);
    await tester.pump();
    expect(reddish(await pixelAt(tester, inRight(const Offset(200, 400)))), isTrue);
    expect(reddish(await pixelAt(tester, inRight(const Offset(200, 300)))), isFalse);

    selection.cancelPreview();
    selection.clear();
    await tester.pump();
    expect(model.isHidden('band'), isFalse);
    expect(reddish(await pixelAt(tester, inRight(const Offset(200, 300)))), isTrue);
  });

  testWidgets('a text box being edited in one view shows as typed in the other', (tester) async {
    final (s, physics, _) = await pumpWorkspace(tester, kind: NotebookKind.canvas);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final [left, right] = tester.widgetList<EditorCanvas>(find.byType(EditorCanvas)).toList();
    final model = left.session.canvas!;
    final box = SurfaceElement(
      id: 'box',
      surfaceId: physics.id,
      type: ElementType.text.name,
      rect: const Rect.fromLTWH(60, 200, 300, 120),
      z: 1,
      createdAt: 1,
      data: const TextData(text: '████████', fontSize: 60, color: 0xFFFF0000).toJson(const {}),
    );
    model.commit(InkEdit(addedElements: [box]));
    await tester.pumpAndSettle();
    final rightBox = tester.getRect(find.byType(EditorCanvas).last);
    Offset inRight(Offset world) => rightBox.topLeft + right.session.viewport.toScreen(world);
    final sample = inRight(const Offset(90, 240));
    final shown = await pixelAt(tester, sample);
    left.session.content.text.edit(model.elementsNear(box.rect).single);
    await tester.pump();
    expect(model.isHidden('box'), isTrue);
    expect(await pixelAt(tester, sample), shown, reason: 'the right view still shows the box');
    left.session.content.text.discard();
    await tester.pump();
  });

  testWidgets('the same in a paged notebook: the page in the other view keeps the selection', (
    tester,
  ) async {
    final (s, physics, _) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final [left, right] = tester.widgetList<EditorCanvas>(find.byType(EditorCanvas)).toList();
    final page = s.pages.pagesOf(physics.id).first;
    final selection = left.session.content.selection;
    final model = selection.model;
    expect(model.surfaceId, page.id);
    model.addStroke(band(page.id));
    await tester.pumpAndSettle();
    final doc = right.session.doc!;
    final rightBox = tester.getRect(find.byType(EditorCanvas).last);
    Offset inRight(Offset onPage) =>
        rightBox.topLeft + doc.viewport.toScreen(doc.layout.frameOf(0)!.topLeft + onPage);
    expect(reddish(await pixelAt(tester, inRight(const Offset(200, 300)))), isTrue);

    selection.select(model.strokesNear(const Rect.fromLTWH(0, 0, 500, 500)), const []);
    await tester.pump();
    expect(model.isHidden('band'), isTrue);
    expect(reddish(await pixelAt(tester, inRight(const Offset(200, 300)))), isTrue);
    selection.clear();
    await tester.pump();
  });
}
