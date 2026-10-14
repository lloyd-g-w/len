import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/zoom/zoom_frame.dart';
import 'package:len/features/editor/zoom/zoom_window_state.dart';

import 'document_editor_test.dart' show pumpEditor, closeEditor;
import 'support/zoom_fixtures.dart';

void main() {
  group('ZoomWindowState', () {
    const frame = ZoomFrame(surfaceId: 'p1', origin: Offset(60.5, 120), scale: 2.75);

    test('round-trips open and closed', () {
      for (final state in const [
        ZoomWindowState(frame: frame, boxHeight: 240),
        ZoomWindowState(frame: frame),
        ZoomWindowState(boxHeight: 180),
        ZoomWindowState(),
      ]) {
        expect(ZoomWindowState.decode(state.encode()), state);
      }
      expect(const ZoomWindowState().isEmpty, isTrue);
      expect(const ZoomWindowState(frame: frame).open, isTrue);
    });

    test('rejects malformed text', () {
      for (final text in [null, '', 'p1,1,2', 'p1,x,2,3,', 'p1,1,2,0,', 'p1,1,2,3,-4', ',,,,y']) {
        expect(ZoomWindowState.decode(text), isNull, reason: '$text');
      }
    });
  });

  testWidgets('a notebook reopens with its zoom window where it was', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    var zoom = await openZoom(tester);
    zoom.dragBy(const Offset(40, 60));
    zoom.dragEnd();
    zoom.boxHeight.value = 260;
    await tester.pumpAndSettle();
    final frame = zoom.frame!;
    await closeEditor(tester);

    await reopenEditor(tester, s, nb);
    zoom = zoomSession(tester).zoomWindow;
    expect(zoom.isOpen, isTrue);
    expect(zoom.frame, frame);
    expect(boxRect(tester).height, 260);
    // Lines start where the frame is.
    expect(zoom.lineStart, closeTo(frame.origin.dx, 1e-9));

    // Closed, it stays closed; the box keeps its height for next time.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    await closeEditor(tester);
    await reopenEditor(tester, s, nb);
    zoom = zoomSession(tester).zoomWindow;
    expect(zoom.isOpen, isFalse);
    expect(zoom.boxHeight.value, 260);
    await closeEditor(tester);
  });

  testWidgets('a frame whose page is gone opens afresh on the page in view', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final page = s.pages.pagesOf(nb.id).first;
    await closeEditor(tester);
    s.settings.setZoomWindow(
      nb.id,
      const ZoomWindowState(
        frame: ZoomFrame(surfaceId: 'gone', origin: Offset(10, 10), scale: 3),
      ).encode(),
    );
    await reopenEditor(tester, s, nb);
    final zoom = zoomSession(tester).zoomWindow;
    expect(zoom.isOpen, isTrue);
    expect(zoom.frame!.surfaceId, page.id);
    await closeEditor(tester);
    s.settings.setZoomWindow(
      nb.id,
      ZoomWindowState(
        frame: ZoomFrame(surfaceId: page.id, origin: const Offset(-500, 1e5), scale: 3),
      ).encode(),
    );
    await reopenEditor(tester, s, nb);
    final kept = zoomSession(tester).zoomWindow;
    expect(kept.isOpen, isTrue);
    expect(kept.frame!.surfaceId, page.id);
    // Kept on its page.
    final bounds = kept.host.boundsOf(page.id)!;
    expect(bounds.contains(kept.frameRect!.topLeft), isTrue);
    expect(kept.frameRect!.bottom, lessThanOrEqualTo(bounds.bottom + 1e-6));
    await closeEditor(tester);
  });
}
