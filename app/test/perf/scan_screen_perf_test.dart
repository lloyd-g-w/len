@Tags(['perf'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/scan/scan_corner_editor.dart';
import 'package:len/features/documents/scan/scan_screen.dart';
import 'package:len/features/documents/scan/scan_session.dart';
import 'package:len/ui/app_theme.dart';

import '../scan_flow_test.dart' show deskPhoto, fakeSources;
import '../support/real_async.dart';
import 'support/big_library.dart';
import 'support/frame_counts.dart';

/// A frame of a corner drag on the scan screen (three pages in the strip):
/// widgets rebuilt and render objects painted while the outline follows
/// the pointer (the photo beneath must not repaint).
///
/// Run: `tool/light.sh flutter test test/perf/scan_screen_perf_test.dart`.
void main() {
  testWidgets('scan screen: drag a corner', (tester) async {
    tester.view
      ..physicalSize = const Size(1000, 1300)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ScanSession();
    for (var i = 0; i < 3; i++) {
      final photo = (await tester.runAsync(() => ScanPhoto.load(deskPhoto())))!;
      session.add(photo);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ScanScreen(
          session: session,
          doneLabel: 'Create notebook',
          sources: fakeSources(camera: []),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => session.display != null && session.pages.every((p) => p.preview != null),
      reason: 'photo and previews',
    );
    await tester.pumpAndSettle();

    // The top-left corner on screen (the photo fitted inside the margin).
    final box = tester.getRect(find.byType(ScanCornerEditor));
    final room = box.deflate(ScanCornerEditor.margin);
    final page = session.current!;
    final photo = Size(page.photo.width.toDouble(), page.photo.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, photo, room.size).destination;
    final fit = Alignment.center.inscribe(fitted, room);
    final corner = fit.topLeft + page.quad.topLeft * (fit.width / photo.width);

    final pointer = await tester.startGesture(corner, kind: PointerDeviceKind.mouse);
    await tester.pump();
    final run = await countFrames((i) async {
      await pointer.moveBy(Offset(i.isEven ? 3 : -2, i.isEven ? 2 : -1));
      await tester.pump(const Duration(milliseconds: 16));
    }, 120);
    report('SCAN corner drag: $run');
    // The photo has a layer of its own: only the outline and loupe repaint.
    expect(run, isNot(contains('_PhotoPainter')));
    await pointer.up();
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
