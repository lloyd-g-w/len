import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_session.dart';
import 'package:len/features/editor/zoom/zoom_frame.dart';
import 'package:len/features/editor/zoom/zoom_window.dart';

import 'split_view_test.dart' show pumpWorkspace;

EditorSession sessionOf(WidgetTester tester, String notebookId) => tester
    .widgetList<EditorCanvas>(find.byType(EditorCanvas))
    .map((c) => c.session)
    .singleWhere((s) => s.notebook.id == notebookId);

void main() {
  testWidgets('a notebook swapped into the first pane keeps its zoom window as it was shown', (
    tester,
  ) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    // Chemistry's window was left open some time ago.
    final page = s.pages.pagesOf(chemistry.id).first;
    final old = ZoomWindowState(
      frame: ZoomFrame(surfaceId: page.id, origin: const Offset(40, 80), scale: 2),
    );
    s.settings.setZoomWindow(chemistry.id, old.encode());
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    expect(sessionOf(tester, chemistry.id).zoomState?.open ?? false, isFalse);

    s.openNotebooks.swapSplit();
    await tester.pumpAndSettle();
    expect(s.openNotebooks.activeId, chemistry.id);
    expect(sessionOf(tester, chemistry.id).zoomState?.open ?? false, isFalse);
  });

  testWidgets('switching tabs away and straight back keeps a zoom window just opened', (
    tester,
  ) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(sessionOf(tester, physics.id).zoomWindow.isOpen, isTrue);
    s.openNotebooks.activate(chemistry.id);
    await tester.pump();
    s.openNotebooks.activate(physics.id);
    await tester.pumpAndSettle();
    expect(sessionOf(tester, physics.id).zoomWindow.isOpen, isTrue);
  });

  testWidgets('a parked pane\'s zoom window does not glide while hidden; it lands when shown', (
    tester,
  ) async {
    final (s, _, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    final session = sessionOf(tester, chemistry.id)..toggleZoomWindow();
    await tester.pumpAndSettle();
    final zoom = session.zoomWindow;
    expect(zoom.frameRect, isNotNull);
    tester.view.physicalSize = const Size(800, 1280); // Parks the second pane.
    await tester.pumpAndSettle();
    final before = zoom.frame!.origin;
    zoom.newLine();
    final end = zoom.state.frame!.origin;
    expect(end, isNot(before));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(zoom.frame!.origin, before, reason: 'no frames run in a parked pane');
    }
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin, end);
  });
}
