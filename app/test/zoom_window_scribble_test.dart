import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/zoom/zoom_window.dart';

import 'document_editor_test.dart' show closeEditor, inkOf, pumpEditor;
import 'support/zoom_fixtures.dart';

void main() {
  testWidgets('a scribble erasing ink in the box does not move the frame on', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    s.preferences.scribbleToErase = true;
    final zoom = await openZoom(tester);
    final page = s.pages.pagesOf(nb.id).first;
    final before = zoom.frame!.origin;
    final paper = boxPaper(tester);
    final y = paper.center.dy;
    final x0 = paper.left + paper.width * 0.72;
    var ms = 0;

    Future<void> stroke(List<Offset> points) async {
      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.down(points.first, timeStamp: Duration(milliseconds: ms += 4));
      for (final p in points.skip(1)) {
        await pen.moveTo(p, timeStamp: Duration(milliseconds: ms += 4));
      }
      await pen.up(timeStamp: Duration(milliseconds: ms += 4));
      await tester.pump();
    }

    List<Offset> line(Offset a, Offset b) {
      final n = ((b - a).distance / 4).ceil();
      return [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];
    }

    final count = inkOf(s, page).length;
    // A word in the advance zone; the pen comes back at once to scribble it out.
    await stroke(line(Offset(x0, y), Offset(x0 + 60, y + 4)));
    expect(inkOf(s, page), hasLength(count + 1));
    await stroke([
      for (var k = 0; k < 8; k++)
        ...line(
          Offset(k.isEven ? x0 - 10 : x0 + 70, y - 8 + k * 3),
          Offset(k.isEven ? x0 + 70 : x0 - 10, y - 5 + k * 3),
        ).skip(k == 0 ? 0 : 1),
    ]);
    expect(inkOf(s, page), hasLength(count), reason: 'the scribble erased the word');
    await tester.pump(ZoomWindow.pause * 2);
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin, before);
    await closeEditor(tester);
  });
}
