// End-to-end, part 3 of 3 (device A again, a new process on the same
// data): everything written before the restart is still there, the
// notebook opens where it was left, and device B's stroke syncs in.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/notebook_card.dart';

import 'support/e2e.dart';
import 'support/flows.dart';

void main() {
  initE2E();

  testWidgets('device A relaunched: state persisted, B\'s edit arrives', (tester) async {
    final s = await launchApp(tester);
    expect(s.notebooks.list().map((n) => n.title).toSet(), {'Field notes', 'Big board'});
    final nb = s.notebooks.list().firstWhere((n) => n.title == 'Field notes');
    final pages = s.pages.pagesOf(nb.id);
    expect(pages, hasLength(3));
    final surfaces = pages.map((p) => "'${p.id}'").join(',');
    int strokes() => count(s, 'strokes', 'surface_id IN ($surfaces)');
    // Its own four strokes survived (B's may already have synced in: the
    // app syncs at launch).
    final own = "device_id = '${s.settings.deviceId()}'";
    expect(count(s, 'strokes', 'surface_id IN ($surfaces) AND $own'), 4);

    final texts = [
      for (final row in s.database.db.select(
        "SELECT data FROM elements WHERE deleted = 0 AND type = 'text'",
      ))
        TextData.fromJson(jsonDecode(row['data'] as String) as Map<String, Object?>).text,
    ];
    expect(texts.toSet(), {'Meeting about photosynthesis', 'Draft on page two'});
    final image = s.database.db.select(
      "SELECT data FROM elements WHERE deleted = 0 AND type = 'image'",
    );
    final sha = ImageData.fromJson(
      jsonDecode(image.single['data'] as String) as Map<String, Object?>,
    ).blob;
    expect(await s.blobs.read(sha), isNotNull, reason: 'the image file survived');

    // The notebook opens on page 2, where it was when the window closed.
    await tester.tap(
      find.ancestor(of: find.text('Field notes'), matching: find.byType(NotebookCard)),
    );
    await pumpUntil(tester, find.byType(PagedDocumentView));
    await settle(tester);
    expect(
      tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller.currentPage,
      1,
    );
    await snapshot(tester, 'c01_reopened');

    // Device B's stroke arrives while the notebook is open.
    if (E2E.server.isNotEmpty) {
      await syncNow(tester, s);
      expect(strokes(), 5);
      await settle(tester);
    }
    await tapTooltip(tester, 'Back');
    await pumpUntil(tester, find.byType(NotebookCard));

    // The canvas still has both far-apart strokes.
    final board = s.notebooks.list().firstWhere((n) => n.title == 'Big board');
    expect(count(s, 'strokes', "surface_id = '${board.id}'"), 2);
    await tester.tap(
      find.ancestor(of: find.text('Big board'), matching: find.byType(NotebookCard)),
    );
    await pumpUntil(tester, find.byType(EditorScreen));
    await settle(tester);
    await snapshot(tester, 'c02_canvas');
    await tapTooltip(tester, 'Back');

    await closeApp(tester);
    expectCleanLog();
  });
}
