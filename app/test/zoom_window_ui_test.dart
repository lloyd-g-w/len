import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_session.dart';
import 'package:len/features/editor/zoom/zoom_box.dart';

import 'document_editor_test.dart' show pumpEditor, inkOf, closeEditor;

EditorSession _session(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;

void main() {
  testWidgets('probe', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final session = _session(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    final zoom = session.zoomWindow;
    print('open ${zoom.isOpen} box ${zoom.box} frame ${zoom.frame} rect ${zoom.frameRect}');
    final box = tester.getRect(find.byType(ZoomBox));
    print('box widget $box');
    final start = box.topLeft + const Offset(60, 80);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(start + Offset(i * 8.0, (i.isEven ? 10 : -10)));
    }
    await g.up();
    await tester.pumpAndSettle();
    final pages = s.pages.pagesOf(nb.id);
    final ink = inkOf(s, pages[0]).where((st) => st.id != 'w1').toList();
    print('strokes ${ink.length} ${ink.map((st) => st.bounds)} width ${ink.map((st) => st.width)}');
    // Write at the right edge
    final r = box.topRight + const Offset(-120, 80);
    final g2 = await tester.startGesture(r, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 5; i++) {
      await g2.moveTo(r + Offset(i * 8.0, 0));
    }
    await g2.up();
    await tester.pump();
    print('after right frame ${zoom.frame}');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    print('after pause frame ${zoom.frame}');
    await closeEditor(tester);
  });
}
