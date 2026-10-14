import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/zoom/zoom_box.dart';

import 'document_editor_test.dart' show pumpEditor, inkOf, closeEditor;
import 'support/zoom_fixtures.dart';

void main() {
  test('the box takes about a third, or the height chosen, leaving the page room', () {
    expect(ZoomBox.heightFor(600), closeTo(216, 1e-9));
    expect(ZoomBox.heightFor(2000), 300);
    expect(ZoomBox.heightFor(600, chosen: 500), 600 - ZoomBox.pageRoom);
    expect(ZoomBox.heightFor(600, chosen: 20), ZoomBox.least);
    expect(ZoomBox.heightFor(2000, chosen: 900), 900, reason: 'past the automatic most');
  });

  testWidgets('a finger drags the top edge to size the box; the pen writes there', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await openZoom(tester);
    final before = boxRect(tester);
    final scale = zoom.frame!.scale;
    final edge = boxPaper(tester).topCenter + const Offset(-80, 4);
    final finger = await tester.startGesture(edge, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 6; i++) {
      await finger.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();
    final after = boxRect(tester);
    expect(after.height, closeTo(before.height + 60, 1));
    expect(after.bottom, before.bottom);
    expect(zoom.boxHeight.value, closeTo(after.height, 0.01));
    expect(zoom.frame!.scale, scale, reason: 'the magnification stays');
    expect(zoom.box.height, closeTo(before.height + 60 - 1, 1));

    // Dragged far up: the page keeps its room.
    await tester.dragFrom(boxPaper(tester).topCenter + const Offset(0, 4), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final tallest = boxRect(tester);
    expect(tallest.height, lessThan(after.height + 2000));
    expect(zoom.boxHeight.value, closeTo(tallest.height, 0.01));

    // A stylus at the edge writes.
    final page = s.pages.pagesOf(nb.id).first;
    final height = boxRect(tester).height;
    final top = boxPaper(tester).topLeft + const Offset(40, 3);
    final pen = await tester.startGesture(top, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 6; i++) {
      await pen.moveBy(const Offset(8, 2));
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(boxRect(tester).height, height);
    expect(inkOf(s, page).where((st) => st.id != 'w1'), hasLength(1));
    await closeEditor(tester);
  });

  testWidgets('left-handed, from the box\'s menu, docks the box at the top', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await openZoom(tester);
    final bottom = boxRect(tester);
    await tester.tap(find.byTooltip('Zoom window options'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic height'), findsNothing, reason: 'no height was dragged');
    await tester.tap(find.text('Left-handed'));
    await tester.pumpAndSettle();
    expect(s.preferences.zoomBoxAtTop, isTrue);
    final top = boxRect(tester);
    expect(top.height, bottom.height);
    expect(top.top, lessThan(bottom.top));
    expect(top.top, lessThan(200), reason: 'under the top bar');
    // The frame shows below it, clear of it.
    final id = zoom.frame!.surfaceId;
    expect(zoom.host.onScreen(id, zoom.frameRect!)!.top, greaterThanOrEqualTo(top.bottom));
    expect(zoom.host.covered.top, greaterThanOrEqualTo(top.bottom - 0.5));

    // Its bottom edge sizes it now, growing downwards.
    final edge = boxPaper(tester).bottomCenter + const Offset(-80, -4);
    await tester.dragFrom(edge, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(boxRect(tester).top, top.top);
    expect(boxRect(tester).height, greaterThan(top.height + 30));

    // Writing works as before.
    await writeInBox(tester, const Offset(0.1, 0.5));
    await tester.pumpAndSettle();
    final page = s.pages.pagesOf(nb.id).first;
    expect(inkOf(s, page).where((st) => st.id != 'w1'), hasLength(1));

    // The menu offers the automatic height back, and right-handed.
    await tester.tap(find.byTooltip('Zoom window options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic height'));
    await tester.pumpAndSettle();
    expect(zoom.boxHeight.value, isNull);
    expect(boxRect(tester).height, top.height);
    await tester.tap(find.byTooltip('Zoom window options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left-handed'));
    await tester.pumpAndSettle();
    expect(s.preferences.zoomBoxAtTop, isFalse);
    expect(boxRect(tester), bottom);
    await closeEditor(tester);
  });
}
