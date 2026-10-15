import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tools/laser_overlay.dart';
import 'package:len/ink/tools/laser.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;
import 'support/zoom_fixtures.dart';

void main() {
  testWidgets('a held laser trail stays where it was when the laser goes on to the next page', (
    tester,
  ) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    final session = zoomSession(tester);
    final doc = session.doc!;
    final tools = session.tools;
    tools.laser = tools.laser.copyWith(fade: LaserFade.pause);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    // Both pages in view.
    doc.applyView(0.3, Offset.zero);
    await tester.pumpAndSettle();
    final first = doc.viewport.toScreen(doc.layout.frameOf(0)!.center);
    final second = doc.viewport.toScreen(doc.layout.frameOf(1)!.center);

    Future<void> write(Offset from) async {
      final g = await tester.startGesture(from, kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(from + Offset(i * 12.0, i * 3.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 16));
    }

    LaserTrail trail() => tester.widget<LaserOverlay>(find.byType(LaserOverlay)).trail;
    await write(first);
    final start = doc.viewport.toScreen(trail().pointAt(0) + doc.layout.frameOf(0)!.topLeft);
    expect(start, first);
    await write(second);
    expect(doc.activePageData.id, doc.pages[1].id);
    final held = trail();
    expect(held.length, greaterThanOrEqualTo(12), reason: 'the first page\'s trail is kept');
    // Still drawn where it was written.
    final active = doc.layout.frameOf(1)!.topLeft;
    expect(doc.viewport.toScreen(held.pointAt(0) + active), first);
    await closeEditor(tester);
  });
}
