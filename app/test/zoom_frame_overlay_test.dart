import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'document_editor_test.dart' show pumpEditor, inkOf, closeEditor;
import 'support/zoom_fixtures.dart';

void main() {
  testWidgets('the frame moves by its tab and sizes with its handle', (tester) async {
    await pumpEditor(tester);
    final zoom = await openZoom(tester);
    final id = zoom.frame!.surfaceId;
    var screen = zoom.host.onScreen(id, zoom.frameRect!)!;
    final mainScale = zoom.host.main.scale;
    final before = zoom.frame!.origin;
    // By its tab, on the top edge at the left.
    await tester.dragFrom(screen.topLeft + const Offset(24, -4), const Offset(-30, -40));
    await tester.pumpAndSettle();
    final moved = zoom.frame!.origin;
    // The drag starts past the touch slop; most of it moves the frame.
    expect(moved.dy, lessThan(before.dy - 20 / mainScale));
    expect(moved.dx, lessThan(before.dx - 10 / mainScale));

    screen = zoom.host.onScreen(id, zoom.frameRect!)!;
    final width = zoom.frameRect!.width;
    await tester.dragFrom(screen.bottomRight, Offset(screen.width * 0.5, screen.height * 0.5));
    await tester.pumpAndSettle();
    expect(zoom.frameRect!.width, greaterThan(width * 1.2));
    expect(zoom.frame!.origin, moved, reason: 'sizing keeps the top-left corner');
    await closeEditor(tester);
  });

  testWidgets('the pen writes inside the frame on the page; the frame stays', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await openZoom(tester);
    final page = s.pages.pagesOf(nb.id).first;
    final id = zoom.frame!.surfaceId;
    final frame = zoom.frame;
    final screen = zoom.host.onScreen(id, zoom.frameRect!)!;
    final pen = await tester.startGesture(
      screen.center - const Offset(30, 0),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 1; i <= 8; i++) {
      await pen.moveBy(const Offset(8, 2));
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(zoom.frame, frame);
    expect(inkOf(s, page).where((st) => st.id != 'w1'), hasLength(1));
    await closeEditor(tester);
  });
}
