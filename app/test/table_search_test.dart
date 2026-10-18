import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/search/editor/text_match_rects.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'content_golden_test.dart' show loadFonts;
import 'table_layout_test.dart' show shopping;

void main() {
  setUpAll(loadFonts);

  test('library search finds cell text; matches are highlighted in their cells', () {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(nb.id).single;
    final data = shopping();
    const box = Rect.fromLTWH(40, 60, 320, 300);
    s.elements.save([
      SurfaceElement(
        id: 't',
        surfaceId: page.id,
        type: 'text',
        rect: box,
        z: 1,
        createdAt: 1,
        data: data.toJson(),
      ),
    ]);
    final hit = s.search.index.search(SearchQuery('sourdough')).single;
    expect(hit.refId, 't');
    expect(s.search.index.search(SearchQuery('sourdough'), notebookId: nb.id), hasLength(1));

    final body = data.text.trim();
    final at = body.indexOf('Milk');
    final rects = textMatchRects(
      json:
          s.database.db.select("SELECT data FROM elements WHERE id = 't'").single['data'] as String,
      box: box,
      rotation: 0,
      body: body,
      ranges: [(start: at, end: at + 4)],
    )!;
    final layout = TextLayout.layout(data, box.width);
    final row = layout.rows[2].rect.shift(box.topLeft);
    layout.dispose();
    final rect = rects.single.single.rect;
    expect(row.contains(rect.center), isTrue);
    expect(rect.left, greaterThan(box.left + 4), reason: 'inside the cell, past its padding');
  });
}
