import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/ink/surface_model.dart';

import 'content_tools_ui_test.dart' show key, liveStrokes;
import 'document_editor_test.dart' show closeEditor, pumpEditor;

/// A curve drawn on one page of a notebook while the other pages are in
/// view (UX_AUDIT R25-29).
void main() {
  late AppServices s;
  late Notebook nb;
  late DocumentController doc;

  Future<void> open(WidgetTester tester) async {
    (s, nb) = await pumpEditor(tester);
    doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools
      ..stylusOnly = true
      ..shape = ShapeKind.curve;
    await tester.pumpAndSettle();
  }

  /// Where [at] (page-local) on page [index] is on screen.
  Offset onPage(int index, Offset at) =>
      doc.viewport.toScreen(doc.layout.frameOf(index)!.topLeft + at);

  Future<void> stylusTap(WidgetTester tester, Offset at) async {
    final pen = await tester.startGesture(at, kind: PointerDeviceKind.stylus);
    await pen.up();
    // Apart, so no tap is the second of a double tap.
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> fingerPan(WidgetTester tester, Offset from) async {
    final finger = await tester.startGesture(from, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await finger.moveTo(from + Offset(0, -12.0 * i));
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();
  }

  List<Stroke> curvesOn(int index) {
    SurfaceModel.flushAll();
    return [
      for (final st in liveStrokes(s, s.pages.pagesOf(nb.id)[index].id))
        if (st.shape?.kind == ShapeKind.curve) st,
    ];
  }

  testWidgets('a finger pan starting on another page keeps the curve being drawn', (tester) async {
    await open(tester);
    expect(doc.layout.visiblePages(doc.viewport.visibleWorld), contains(1), reason: 'in view');
    await stylusTap(tester, onPage(0, const Offset(100, 300)));
    // With one anchor, a page switch would have dropped it.
    await fingerPan(tester, onPage(1, const Offset(200, 100)));
    expect(doc.activePageData.id, s.pages.pagesOf(nb.id).first.id);
    await stylusTap(tester, onPage(0, const Offset(300, 350)));
    await stylusTap(tester, onPage(0, const Offset(400, 300)));
    await key(tester, LogicalKeyboardKey.enter);
    expect(curvesOn(0).single.shape!.anchorCount, 3);
    expect(curvesOn(1), isEmpty);
    await closeEditor(tester);
  });

  testWidgets('a stylus tap on another page finishes the curve and starts one there', (
    tester,
  ) async {
    await open(tester);
    await stylusTap(tester, onPage(0, const Offset(100, 300)));
    await stylusTap(tester, onPage(0, const Offset(300, 350)));
    await stylusTap(tester, onPage(1, const Offset(200, 100)));
    expect(curvesOn(0).single.shape!.anchorCount, 2, reason: 'finished where it was drawn');
    await stylusTap(tester, onPage(1, const Offset(300, 150)));
    await key(tester, LogicalKeyboardKey.enter);
    expect(curvesOn(1).single.shape!.anchorCount, 2);
    await closeEditor(tester);
  });
}
