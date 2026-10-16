@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/features/editor/document/document_layout.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/sidebar/page_sidebar.dart';
import 'package:len/ui/app_theme.dart';

import '../support/zoom_fixtures.dart';
import 'support/big_library.dart';

/// The page sidebar while the page beside it scrolls (a 200-page notebook
/// of handwriting, desktop-sized): a frame that stays on a page costs the
/// sidebar nothing (no rebuild, no paint); a frame on which the page on
/// screen changes rebuilds only the two numbers concerned, repainting no
/// thumbnail for it (the column following the page brings new tiles in,
/// which load as in the overview).
///
/// Run: `tool/light.sh flutter test test/perf/page_sidebar_perf_test.dart`.
void main() {
  testWidgets('scrolling within a page: nothing in the sidebar', (tester) async {
    final s = await _open(tester);
    final doc = zoomSession(tester).doc!;
    final page = doc.currentPage;
    final run = await _count(tester, 120, (i) => doc.viewport.panBy(Offset(0, i.isEven ? -6 : 5)));
    expect(doc.currentPage, page);
    report('sidebar, scroll within a page: $run');
    expect(run.rebuilds, 0, reason: '$run');
    expect(run.paints, 0, reason: '$run');
    await _close(tester, s);
  });

  testWidgets('scrolling across pages: the highlight moves, nothing else', (tester) async {
    final s = await _open(tester);
    final doc = zoomSession(tester).doc!;
    final first = doc.currentPage;
    // About a page every 10 frames, for 120 frames.
    final step = doc.layout.frameOf(1)!.top * doc.viewport.scale / 10;
    final run = await _count(tester, 120, (_) => doc.viewport.panBy(Offset(0, -step)));
    final pages = doc.currentPage - first;
    expect(pages, greaterThan(8));
    report('sidebar, scroll across $pages pages: $run');
    // Each change: the two numbers concerned (with their semantics). The
    // column follows the page, so a tile comes into view now and then
    // (built and recorded once); thumbnails repaint (an image each) only
    // when the cache has a new one, never for the highlight.
    expect(run.rebuildsOf('SidebarTile'), lessThanOrEqualTo(pages), reason: '$run');
    expect(run.rebuildsOf('_Number'), lessThanOrEqualTo(pages * 3), reason: '$run');
    expect(run.rebuilds / pages, lessThan(100), reason: '$run');
    expect(run.paintsOf('CP:_ThumbnailPainter') / pages, lessThan(12), reason: '$run');
    await _close(tester, s);
  });
}

/// Rebuilds and paints inside the sidebar over [n] frames of [step].
class _Run {
  int rebuilds = 0;
  int paints = 0;
  final built = <String, int>{};
  final painted = <String, int>{};

  int rebuildsOf(String type) => built[type] ?? 0;
  int paintsOf(String type) => painted[type] ?? 0;

  @override
  String toString() {
    String top(Map<String, int> m) => (m.entries.toList()..sort((a, b) => b.value - a.value))
        .take(8)
        .map((e) => '${e.key} ${e.value}')
        .join(', ');
    return '$rebuilds rebuilds (${top(built)}), $paints paints (${top(painted)})';
  }
}

Future<_Run> _count(WidgetTester tester, int n, void Function(int i) step) async {
  for (var i = 0; i < 10; i++) {
    step(i);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(seconds: 1)); // Follow-up glides end.
  final run = _Run();
  final sidebar = tester.renderObject(find.byType(PageSidebar));
  bool inSidebar(RenderObject r) {
    for (RenderObject? n = r; n != null; n = n.parent) {
      if (n == sidebar) return true;
    }
    return false;
  }

  debugOnRebuildDirtyWidget = (e, _) {
    if (e.widget is! PageSidebar && e.findAncestorWidgetOfExactType<PageSidebar>() == null) return;
    run.rebuilds++;
    final name = e.widget.runtimeType.toString();
    run.built[name] = (run.built[name] ?? 0) + 1;
  };
  debugProfilePaintsEnabled = true;
  debugOnProfilePaint = (r) {
    if (r.isRepaintBoundary && !r.debugNeedsPaint) return;
    if (!inSidebar(r)) return;
    run.paints++;
    final painter = r is RenderCustomPaint ? r.painter : null;
    final name = painter == null ? r.runtimeType.toString() : 'CP:${painter.runtimeType}';
    run.painted[name] = (run.painted[name] ?? 0) + 1;
  };
  try {
    for (var i = 0; i < n; i++) {
      step(i);
      await tester.pump(const Duration(milliseconds: 16));
    }
  } finally {
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
    debugProfilePaintsEnabled = false;
  }
  return run;
}

Future<AppServices> _open(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (s, nb) = lectureNotebook(pages: 200, lines: 12);
  s.settings.setPageSidebar(nb.id, true);
  await tester.pumpWidget(
    AppScope(
      services: s,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(PageSidebar), findsOneWidget);
  expect(zoomSession(tester).doc!.flow, PageFlow.continuous);
  return s;
}

Future<void> _close(WidgetTester tester, AppServices s) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
  s.dispose();
}
