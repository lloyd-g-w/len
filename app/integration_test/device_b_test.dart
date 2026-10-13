// End-to-end, part 2 of 3 (device B, its own data directory): syncs what
// device A wrote, checks it arrived intact, adds a stroke and syncs it back.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/notebook_card.dart';

import 'support/e2e.dart';
import 'support/flows.dart';

void main() {
  initE2E();

  testWidgets('device B: receives device A\'s notebooks and adds to one', (tester) async {
    final s = await launchApp(tester);
    expect(s.notebooks.list(), isEmpty);
    await connectSync(tester, s);
    await pumpUntil(tester, find.text('Field notes'));
    expect(s.notebooks.list().map((n) => n.title).toSet(), {'Field notes', 'Big board'});

    final nb = s.notebooks.list().firstWhere((n) => n.title == 'Field notes');
    final pages = s.pages.pagesOf(nb.id);
    expect(pages, hasLength(3));
    final surfaces = pages.map((p) => "'${p.id}'").join(',');
    expect(count(s, 'strokes', 'surface_id IN ($surfaces)'), 4);
    final texts = [
      for (final row in s.database.db.select(
        "SELECT data FROM elements WHERE deleted = 0 AND type = 'text'",
      ))
        TextData.fromJson(jsonDecode(row['data'] as String) as Map<String, Object?>),
    ];
    final data = texts.firstWhere((t) => t.text == 'Meeting about photosynthesis');
    expect(data.spans.single.style.bold, isTrue);

    // Opening the notebook shows the image: its blob is fetched on demand.
    final image = s.database.db.select(
      "SELECT data FROM elements WHERE deleted = 0 AND type = 'image'",
    );
    final sha = ImageData.fromJson(
      jsonDecode(image.single['data'] as String) as Map<String, Object?>,
    ).blob;
    await tester.tap(
      find.ancestor(of: find.text('Field notes'), matching: find.byType(NotebookCard)),
    );
    await pumpUntil(tester, find.byType(EditorScreen));
    await settle(tester);
    var fetched = false;
    await waitFor(tester, () {
      s.blobs.has(sha).then((v) => fetched = v);
      return fetched;
    }, reason: 'the image blob downloaded');
    await snapshot(tester, 'b01_field_notes');

    // Write on page 1 and sync it back.
    final c = tester.getCenter(find.byType(EditorScreen));
    await press(tester, LogicalKeyboardKey.keyP);
    await stylusStroke(tester, wave(c + const Offset(-100, 200)));
    expect(count(s, 'strokes', 'surface_id IN ($surfaces)'), 5);
    await tapTooltip(tester, 'Back');
    await pumpUntil(tester, find.byType(NotebookCard));
    await syncNow(tester, s);

    await closeApp(tester);
    expectCleanLog();
  });
}
