import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/scan/scan_session.dart';

import 'scan_flow_test.dart' show deskPhoto;
import 'support/real_async.dart';

void main() {
  testWidgets('a corner drag moves the outline; the session hears only what else changes', (
    tester,
  ) async {
    final session = ScanSession();
    addTearDown(session.dispose);
    session.add((await tester.runAsync(() => ScanPhoto.load(deskPhoto())))!);
    await pumpUntil(tester, () => session.current!.preview != null, reason: 'preview');
    var heard = 0, moved = 0;
    session.addListener(() => heard++);
    session.outline.addListener(() => moved++);
    final page = session.current!;
    final found = page.quad;

    // A move: the outline only (the strip shows the preview, not the shape).
    session.setQuad(found.withCorner(0, found.topLeft + const Offset(3, 2)), preview: false);
    expect((moved, heard), (1, 0));
    expect(session.isWholePhoto, isFalse);

    // Onto the whole photo: Whole photo lights up.
    session.setQuad(page.photo.bounds, preview: false);
    expect((moved, heard), (2, 1));
    expect(session.isWholePhoto, isTrue);

    // Off it again.
    session.setQuad(found, preview: false);
    expect((moved, heard), (3, 2));

    // The drag's end renders the preview.
    session.updatePreview();
    expect(heard, 3);

    // Without a preview yet the strip shows the outline's shape: it follows.
    session.add((await tester.runAsync(() => ScanPhoto.load(deskPhoto())))!);
    heard = 0;
    final next = session.current!;
    expect(next.preview, isNull);
    session.setQuad(
      next.quad.withCorner(0, next.quad.topLeft + const Offset(4, 0)),
      preview: false,
    );
    expect(heard, 1);

    // Whole photo (no drag) notifies both.
    moved = heard = 0;
    session.toggleWholePhoto();
    expect(moved, 1);
    expect(heard, greaterThan(0));
    await pumpUntil(tester, () => session.pages.every((p) => p.preview != null), reason: 'done');
  });
}
