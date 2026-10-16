@Tags(['perf'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/document_painters.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ui/app_theme.dart';

import '../support/zoom_fixtures.dart';
import 'support/big_library.dart';

/// The zoom window on a notebook of full pages: what a frame of the page
/// view scrolling costs with the window open (and closed), and what a pen
/// move in the box costs while writing line after line (widgets rebuilt,
/// render objects painted, the box's own painters, time in the harness).
///
/// Run: `tool/light.sh flutter test test/perf/zoom_window_perf_test.dart`.
void main() {
  for (final open in [false, true]) {
    testWidgets('full pages: scroll the page view, zoom window ${open ? 'open' : 'closed'}', (
      tester,
    ) async {
      await _pumpNotebook(tester);
      if (open) await openZoom(tester);
      final viewport = zoomSession(tester).doc!.viewport;
      final run = await _measure(tester, (i) async {
        viewport.panBy(Offset(0, i.isEven ? -6.1 : 5.3));
        await tester.pump(const Duration(milliseconds: 16));
      }, 120);
      report('ZOOM ${open ? 'open  ' : 'closed'} scroll: $run');
      await _close(tester);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  for (final box in [false, true]) {
    testWidgets('full pages: write 60 words ${box ? 'in the zoom box' : 'on the page'}', (
      tester,
    ) async {
      await _pumpNotebook(tester);
      final zoom = box ? await openZoom(tester) : null;
      var word = 0;
      // A word: down, 10 moves, up, as a pen writes along the line (in the
      // box, or on the page's lines at the same size).
      Future<void> step(int i) async {
        final at = i % 12;
        if (at == 0) {
          final area = box ? boxPaper(tester) : const Rect.fromLTWH(120, 300, 700, 120);
          final x = area.left + 30 + (word % 6) * (area.width - 80) / 6;
          _pen = await tester.startGesture(
            Offset(x, area.bottom - area.height * 0.4),
            kind: PointerDeviceKind.stylus,
          );
          word++;
        } else if (at == 11) {
          await _pen!.up();
        } else {
          await _pen!.moveBy(Offset(5, at.isEven ? 7 : -7));
        }
        await tester.pump(const Duration(milliseconds: 8));
      }

      final run = await _measure(tester, step, 60 * 12, warmUp: 12 * 12);
      report('ZOOM write ${box ? 'in box ' : 'on page'}: $run');
      if (zoom != null) report('ZOOM frame moved on to ${zoom.frame!.origin}');
      await _close(tester);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

TestGesture? _pen;

Future<String> _measure(
  WidgetTester tester,
  Future<void> Function(int i) step,
  int n, {
  int warmUp = 20,
}) async {
  for (var i = 0; i < warmUp; i++) {
    await step(i);
  }
  var rebuilds = 0;
  final built = <String, int>{};
  final painted = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    rebuilds++;
    final name = e.widget.runtimeType.toString();
    built[name] = (built[name] ?? 0) + 1;
  };
  debugProfilePaintsEnabled = true;
  debugOnProfilePaint = (r) {
    final painter = r is RenderCustomPaint ? r.painter : null;
    final name = switch (painter) {
      DocumentPaperPainter() ||
      CommittedInkPainter() ||
      LiveInkPainter() => 'CP:${painter.runtimeType}',
      _ => r.runtimeType.toString(),
    };
    painted[name] = (painted[name] ?? 0) + 1;
  };
  final watch = Stopwatch()..start();
  for (var i = warmUp; i < warmUp + n; i++) {
    await step(i);
  }
  watch.stop();
  debugOnRebuildDirtyWidget = null;
  debugOnProfilePaint = null;
  debugProfilePaintsEnabled = false;
  String per(Map<String, int> counts) => counts.entries
      .where((e) => e.value >= n ~/ 12)
      .map((e) => '${e.key} ${(e.value / n).toStringAsFixed(1)}')
      .join(', ');
  final paints = painted.values.fold(0, (a, b) => a + b);
  return '${(rebuilds / n).toStringAsFixed(1)} rebuilds (${per(built)}), '
      '${(paints / n).toStringAsFixed(1)} paints (${per(painted)}), '
      '${(watch.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms a frame';
}

/// A notebook of three ruled pages full of handwriting (≈ 1,900 strokes
/// each) in a tablet-sized editor.
Future<void> _pumpNotebook(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1000, 1300)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = BenchClock();
  final services = AppServices.create(AppDatabase.inMemory(), clock: clock);
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Lectures',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  final first = services.pages.pagesOf(nb.id).single;
  for (var i = 0; i < 2; i++) {
    services.pages.addPage(
      nb.id,
      template: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
    );
  }
  for (final (i, page) in services.pages.pagesOf(nb.id).indexed) {
    services.strokes.save(pageOfInk(page.id, clock, lines: 25, seed: i + (first.id.length)));
  }
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}
