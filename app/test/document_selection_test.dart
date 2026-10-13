import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/sync/sync_engine.dart';

import 'content_documents_test.dart' show ctrl, elementsOf;
import 'content_tools_ui_test.dart' show key, mouseDrag;
import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;

/// Lasso selections spanning the pages of a paged notebook in continuous
/// scrolling, and selections moved from one page onto another.
///
/// The coordinates are for a toolbar docked at the top at 800 × 1300 (page 1
/// ends at ~949 px on screen, page 2 starts just below it, ~966 px); [up]
/// moves them to where the pages are with the toolbar at the bottom.
/// Laid out for a toolbar docked at the top in a 72-dp band; at 800 px
/// it is a 48-dp row under the bar, so the pages sit higher on screen by
/// the difference.
double _up = 0;
List<Offset> up(List<Offset> points) => [for (final p in points) p.translate(0, -_up)];
Future<void> _measure(WidgetTester tester) async =>
    _up = 72 - tester.widget<EditorChrome>(find.byType(EditorChrome)).layout.toolRowHeight;

void main() {
  Future<void> lasso(WidgetTester tester, Rect r) => mouseDrag(tester, [
    r.topLeft,
    r.topRight,
    r.bottomRight,
    r.bottomLeft,
    r.topLeft + const Offset(0, 8),
  ]);

  Set<String> ids(List<Stroke> strokes) => {for (final s in strokes) s.id};

  testWidgets('a lasso across the page gap selects on both pages; move, delete, undo', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester);
    await _measure(tester);
    final pages = s.pages.pagesOf(nb.id);
    await drawAt(tester, up(const [Offset(300, 880)]).single); // Page 1, near its bottom.
    await drawAt(tester, up(const [Offset(300, 1010)]).single); // Page 2, near its top.
    final before1 = inkOf(s, pages[0]).where((st) => st.id != 'w1').single;
    final before2 = inkOf(s, pages[1]).where((st) => st.id != 'w2').single;

    await key(tester, LogicalKeyboardKey.keyL);
    await lasso(tester, const Rect.fromLTRB(250, 850, 440, 1060).translate(0, -_up));
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/selection_across_pages.png'),
    );

    // Move both by 40 px to the right: each stays on its page.
    await mouseDrag(tester, up(const [Offset(330, 960), Offset(350, 960), Offset(370, 960)]));
    final moved1 = inkOf(s, pages[0]).where((st) => st.id != 'w1').single;
    final moved2 = inkOf(s, pages[1]).where((st) => st.id != 'w2').single;
    expect(moved1.id, isNot(before1.id));
    expect(moved2.id, isNot(before2.id));
    expect(moved1.points.first.x - before1.points.first.x, greaterThan(40));
    expect(moved2.points.first.y, closeTo(before2.points.first.y, 0.01));
    expect(find.byTooltip('Delete (Del)'), findsOneWidget); // Still selected.

    // One undo puts both back.
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(ids(inkOf(s, pages[0])), {'w1', before1.id});
    expect(ids(inkOf(s, pages[1])), {'w2', before2.id});

    // Delete across both pages, one undo.
    await lasso(tester, const Rect.fromLTRB(250, 850, 440, 1060).translate(0, -_up));
    await tester.tap(find.byTooltip('Delete (Del)'));
    await tester.pump();
    expect(ids(inkOf(s, pages[0])), {'w1'});
    expect(ids(inkOf(s, pages[1])), {'w2'});
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(ids(inkOf(s, pages[0])), {'w1', before1.id});
    expect(ids(inkOf(s, pages[1])), {'w2', before2.id});
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('a selection dropped onto the next page moves there (one undo step)', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    await _measure(tester);
    final pages = s.pages.pagesOf(nb.id);
    await drawAt(tester, up(const [Offset(300, 880)]).single); // Page 1.
    // Where the stroke should land on page 2, drawn there for reference.
    await drawAt(tester, up(const [Offset(300, 1030)]).single);
    final original = inkOf(s, pages[0]).where((st) => st.id != 'w1').single;
    final reference = inkOf(s, pages[1]).where((st) => st.id != 'w2').single;

    // A text box on page 1 too, moved along with the ink.
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, up(const [Offset(400, 860)]));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('text-box-field')), 'Moves');
    await tester.tap(find.byTooltip('Done (Esc)'));
    await tester.pumpAndSettle();
    final box = elementsOf(s, pages[0].id).single;

    await key(tester, LogicalKeyboardKey.keyL);
    await lasso(tester, const Rect.fromLTRB(250, 840, 600, 930).translate(0, -_up));
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);
    await mouseDrag(tester, up(const [Offset(330, 890), Offset(330, 960), Offset(330, 1040)]));

    expect(ids(inkOf(s, pages[0])), {'w1'});
    final moved = inkOf(s, pages[1]).where((st) => st.id != 'w2' && st.id != reference.id).single;
    expect(moved.surfaceId, pages[1].id);
    // In page 2's coordinates, where the reference stroke was drawn.
    expect(moved.points.first.x, closeTo(reference.points.first.x, 1.5));
    expect(moved.points.first.y, closeTo(reference.points.first.y, 1.5));
    expect(elementsOf(s, pages[0].id), isEmpty);
    final movedBox = elementsOf(s, pages[1].id).single;
    expect(movedBox.id, box.id); // Re-parented, same id.
    expect(movedBox.surfaceId, pages[1].id);
    expect(movedBox.rect.top, lessThan(box.rect.top));

    // Still selected: it can be moved back onto page 1.
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(ids(inkOf(s, pages[0])), {'w1', original.id});
    expect(ids(inkOf(s, pages[1])), {'w2', reference.id});
    expect(elementsOf(s, pages[0].id).single.rect, box.rect);
    expect(elementsOf(s, pages[1].id), isEmpty);

    await tester.tap(find.byTooltip('Redo (Ctrl+Shift+Z)'));
    await tester.pump();
    expect(ids(inkOf(s, pages[0])), {'w1'});
    expect(elementsOf(s, pages[1].id).single.id, box.id);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('a page deleted elsewhere under a selection spanning it drops the selection', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester);
    await _measure(tester);
    final pages = s.pages.pagesOf(nb.id);
    await drawAt(tester, up(const [Offset(300, 880)]).single); // Page 1.
    await drawAt(tester, up(const [Offset(300, 1010)]).single); // Page 2.
    final kept = inkOf(s, pages[0]).where((st) => st.id != 'w1').single;
    await key(tester, LogicalKeyboardKey.keyL);
    await lasso(tester, const Rect.fromLTRB(250, 850, 440, 1060).translate(0, -_up));
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);

    // Page 2 is deleted on another device.
    s.pages.delete(pages[1].id);
    s.sync.debugAnnounce(RemoteChanges()..pagesOfNotebooks.add(nb.id));
    await tester.pump();
    expect(find.byTooltip('Delete (Del)'), findsNothing);
    await key(tester, LogicalKeyboardKey.delete); // Nothing selected: nothing goes.
    expect(ids(inkOf(s, pages[0])), {'w1', kept.id});
    expect(s.pages.get(pages[1].id), isNull);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });
}
