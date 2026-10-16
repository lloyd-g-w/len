import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_scope.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/finger_reading.dart';
import 'package:len/ink/input/canvas_gestures.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'canvas_gestures_test.dart' show down, ms, move, up;
import 'document_editor_test.dart' show closeEditor, inkOf, pumpEditor;
import 'support/page_actions.dart';
import 'support/real_async.dart';

/// R20-6: reading on a phone without a stylus. While fingers draw, a page
/// with content opens in reading (one finger scrolls) until a tool is
/// chosen, and goes back to it after a while without writing.
void main() {
  group('ToolSettings.reading', () {
    test('only while no stylus was seen; then fingers navigate', () {
      final tools = ToolSettings()..reading = true;
      expect(tools.reading, isTrue);
      expect(tools.fingersNavigate, isTrue);
      tools.stylusOnly = true; // A stylus was seen.
      expect(tools.reading, isFalse);
      expect(tools.fingersNavigate, isTrue, reason: 'palm rejection');
      tools.reading = true;
      expect(tools.reading, isFalse, reason: 'never once stylus-only is decided');
      tools.stylusOnly = false; // Draw with finger, chosen.
      tools.reading = true;
      expect(tools.reading, isFalse);
      expect(tools.fingersNavigate, isFalse);
    });

    test('any tool, option or quick slot chosen writes', () {
      final tools = ToolSettings();
      var notified = 0;
      tools.addListener(() => notified++);
      void read() => tools.reading = true;

      read();
      tools.pick(EditorTool.pen); // The active tool, tapped.
      expect((tools.reading, tools.tool), (false, EditorTool.pen));
      read();
      tools.tool = EditorTool.highlighter;
      expect(tools.reading, isFalse);
      read();
      tools.togglePrevious();
      expect(tools.reading, isFalse);
      read();
      tools.selectColor(1);
      expect(tools.reading, isFalse);
      read();
      tools.selectWidth(0);
      expect(tools.reading, isFalse);
      read();
      tools.eraser = tools.eraser;
      expect(tools.reading, isFalse);
      read();
      tools.tool = tools.tool; // Unchanged (programmatic): stays.
      expect(tools.reading, isTrue);
      final before = notified;
      tools.pick(tools.tool);
      tools.pick(tools.tool); // Writing already: nothing.
      expect(notified, before + 1);
      tools.dispose();
    });
  });

  group('FingerReading', () {
    late ToolSettings tools;
    var content = true;
    var busy = false;
    var touch = true;
    late int reads;

    FingerReading reading() => FingerReading(
      tools: tools,
      hasContent: () => content,
      busy: () => busy,
      touchFirst: () => touch,
    )..onRead = () => reads++;

    setUp(() {
      FingerReading.debugEnabled = true;
      tools = ToolSettings();
      content = true;
      busy = false;
      touch = true;
      reads = 0;
    });
    tearDown(() => tools.dispose());

    test('opens in reading where there is content, in writing where there is none', () {
      final r = reading()..open();
      expect(tools.reading, isTrue);
      expect(reads, 1);
      r.dispose();

      tools.reading = false;
      content = false;
      final empty = reading()..open();
      expect(tools.reading, isFalse);
      expect(reads, 1);
      empty.dispose();
    });

    test('back to reading after two minutes without writing; writing starts it over', () {
      fakeAsync((async) {
        final r = reading()..open();
        tools.pick(EditorTool.pen);
        expect(tools.reading, isFalse);
        async.elapse(const Duration(seconds: 90));
        r.wrote();
        async.elapse(const Duration(seconds: 90));
        expect(tools.reading, isFalse, reason: 'wrote 90 s ago');
        async.elapse(const Duration(seconds: 31));
        expect(tools.reading, isTrue);
        expect(reads, 2);

        // Typing or a selection holds it off; an empty page never reads.
        tools.pick(EditorTool.pen);
        busy = true;
        async.elapse(FingerReading.idle * 2);
        expect(tools.reading, isFalse);
        busy = false;
        content = false;
        async.elapse(FingerReading.idle);
        expect(tools.reading, isFalse);
        content = true;
        async.elapse(FingerReading.idle);
        expect(tools.reading, isTrue);

        // A tool chosen counts as writing too.
        tools.pick(EditorTool.pen);
        async.elapse(const Duration(seconds: 100));
        tools.tool = EditorTool.highlighter;
        async.elapse(const Duration(seconds: 100));
        expect(tools.reading, isFalse);
        r.dispose();
        async.elapse(FingerReading.idle);
        expect(tools.reading, isFalse, reason: 'disposed');
      });
    });

    test('a blank page added writes', () {
      final r = reading()..open();
      r.write();
      expect(tools.reading, isFalse);
      r.dispose();
    });

    test('never with a stylus seen, nor with a mouse', () {
      fakeAsync((async) {
        tools.stylusOnly = true;
        final stylus = reading()..open();
        async.elapse(FingerReading.idle * 2);
        expect(tools.reading, isFalse);
        stylus.dispose();
        tools.stylusOnly = null;
        touch = false;
        final mouse = reading()..open();
        async.elapse(FingerReading.idle * 2);
        expect(tools.reading, isFalse);
        mouse.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('input in each state', () {
    late AppDatabase db;
    late SurfaceModel model;
    late ViewportController viewport;
    late ToolSettings tools;
    late ContentTools content;
    late InkInputController input;
    late List<Offset> menus;
    late List<Offset> doubleTaps;

    setUp(() {
      db = AppDatabase.inMemory();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
      );
      viewport = ViewportController()..setSize(const Size(400, 800));
      tools = ToolSettings();
      final live = LiveInk();
      content = ContentTools(
        model: model,
        viewport: viewport,
        tools: tools,
        live: live,
        clipboard: InkClipboard(),
      );
      menus = [];
      doubleTaps = [];
      input = InkInputController(
        model: model,
        viewport: viewport,
        tools: tools,
        live: live,
        content: content,
        gestures: CanvasGestures(onContextMenu: menus.add)..onDoubleTap = doubleTaps.add,
      );
    });

    tearDown(() {
      content.dispose();
      model.dispose();
      db.close();
    });

    void drag(int id, Offset from, Offset to, {int t = 0}) => input
      ..handleDown(down(id, from, t: t))
      ..handleMove(move(id, Offset.lerp(from, to, 0.5)!, t: t + 10))
      ..handleMove(move(id, to, t: t + 20))
      ..handleUp(up(id, to, t: t + 30));

    void tap(int id, Offset at, {required int t}) => input
      ..handleDown(down(id, at, t: t))
      ..handleUp(up(id, at, t: t + 60));

    test('reading: one finger scrolls and double-taps; writing: it draws', () {
      tools.reading = true;
      drag(1, const Offset(200, 600), const Offset(200, 300));
      expect(model.loadedStrokeCount, 0);
      expect(viewport.offset.dy, closeTo(-300 + kTouchSlop, 1));
      tap(2, const Offset(100, 100), t: 1000);
      tap(3, const Offset(100, 100), t: 1200);
      expect(doubleTaps, hasLength(1));
      expect(model.loadedStrokeCount, 0, reason: 'taps are no dots');

      tools.pick(EditorTool.pen);
      final before = viewport.offset;
      drag(4, const Offset(100, 400), const Offset(300, 450), t: 3000);
      expect(model.loadedStrokeCount, 1);
      expect(viewport.offset, before);
      // Two fingers still scroll while writing.
      input
        ..handleDown(down(5, const Offset(100, 400), t: 4000))
        ..handleDown(down(6, const Offset(300, 400), t: 4005))
        ..handleMove(move(5, const Offset(100, 200), t: 4020))
        ..handleMove(move(6, const Offset(300, 200), t: 4020))
        ..handleUp(up(5, const Offset(100, 200), t: 4030))
        ..handleUp(up(6, const Offset(300, 200), t: 4030));
      expect(model.loadedStrokeCount, 1);
      expect(viewport.offset.dy, lessThan(before.dy - 100));
    });

    testWidgets('reading: a still finger opens the menu', (tester) async {
      tools.reading = true;
      input.handleDown(down(1, const Offset(200, 200)));
      await tester.pump(ms(700));
      input.handleUp(up(1, const Offset(200, 200), t: 700));
      expect(menus, [const Offset(200, 200)]);
      expect(model.loadedStrokeCount, 0);
    });
  });

  group('in the editor, on a phone', () {
    const phone = Size(390, 844);
    const tip = 'Reading: one finger scrolls; tap the pen to write';
    setUp(() => FingerReading.debugEnabled = true);

    ToolSettings toolsOf(WidgetTester tester) =>
        tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools;
    DocumentController docOf(WidgetTester tester) =>
        tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    Future<void> fingerDrag(WidgetTester tester, Offset from, Offset by) async {
      final finger = await tester.startGesture(from);
      for (var i = 1; i <= 10; i++) {
        await finger.moveTo(from + by * (i / 10));
      }
      await finger.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a page with ink opens in reading: one finger scrolls, the pen writes', (
      tester,
    ) async {
      final (s, nb) = await pumpEditor(tester, size: phone);
      final first = s.pages.pagesOf(nb.id).first;
      final tools = toolsOf(tester);
      expect(tools.reading, isTrue);
      expect(find.text(tip), findsOneWidget);
      expect(find.byTooltip('Pen: tap to write'), findsOneWidget);

      final before = docOf(tester).viewport.offset;
      await fingerDrag(tester, const Offset(200, 600), const Offset(0, -300));
      expect(inkOf(s, first), hasLength(1), reason: 'no ink: it scrolled');
      expect(docOf(tester).viewport.offset.dy, lessThan(before.dy - 100));

      // The pen (the switcher, in its reading outline) writes.
      await tester.tap(find.byKey(const ValueKey('tool-switcher')));
      await tester.pumpAndSettle();
      expect(tools.reading, isFalse);
      expect(find.text(tip), findsNothing);
      expect(s.settings.seenTips, contains(EditorTip.reading.name), reason: 'done');
      expect(find.byTooltip('Pen: tap to switch tools'), findsOneWidget);
      final page = docOf(tester).currentPage;
      final shown = s.pages.pagesOf(nb.id)[page];
      final ink = inkOf(s, shown).length;
      await fingerDrag(tester, const Offset(120, 400), const Offset(120, 30));
      await tester.pump(const Duration(seconds: 1)); // Written behind.
      expect(inkOf(s, shown), hasLength(ink + 1));

      // Two minutes without writing: reading again (no second tip).
      await tester.pump(FingerReading.idle);
      await tester.pumpAndSettle();
      expect(tools.reading, isTrue);
      expect(find.text(tip), findsNothing);

      // A quick colour slot writes too.
      await tester.tap(find.byKey(const ValueKey('color-1')));
      await tester.pumpAndSettle();
      expect(tools.reading, isFalse);
      expect(tools.activeConfig.colorIndex, 1);
      await closeEditor(tester);
    });

    testWidgets('reading still double-tap zooms and long-presses for the menu', (tester) async {
      await pumpEditor(tester, size: phone);
      expect(toolsOf(tester).reading, isTrue);
      final scale = docOf(tester).viewport.scale;
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(200, 400));
      await tester.pumpAndSettle();
      expect(docOf(tester).viewport.scale, greaterThan(scale * 1.5));

      await tester.longPressAt(const Offset(200, 450));
      await tester.pumpAndSettle();
      expect(find.text('Add text here'), findsOneWidget);
      await closeEditor(tester);
    });

    testWidgets('something pasted (or inserted) while reading writes: a finger moves it', (
      tester,
    ) async {
      final (s, nb) = await pumpEditor(tester, size: phone);
      final tools = toolsOf(tester);
      expect(tools.reading, isTrue);
      final ink = inkOf(s, s.pages.pagesOf(nb.id).first);
      s.clipboard.put(ink, const [], ink.first.bounds);
      await tester.longPressAt(const Offset(200, 450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste here'));
      await pumpUntil(tester, () => inkOf(s, s.pages.pagesOf(nb.id).first).length == 2);
      await tester.pumpAndSettle();
      expect(tools.reading, isFalse, reason: 'the pasted ink is selected, to move by finger');
      await closeEditor(tester);
    });

    testWidgets('presenting with the laser never goes back to reading', (tester) async {
      await pumpEditor(tester, size: phone);
      final tools = toolsOf(tester);
      expect(tools.reading, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect((tools.tool, tools.reading), (EditorTool.laser, false));
      await tester.pump(FingerReading.idle * 2);
      await tester.pumpAndSettle();
      expect(tools.reading, isFalse, reason: 'the finger still points');
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      await closeEditor(tester);
    });

    testWidgets('a blank page added writes; a stylus ends reading for good', (tester) async {
      final (s, _) = await pumpEditor(tester, size: phone);
      final tools = toolsOf(tester);
      expect(tools.reading, isTrue);
      await addPageAfter(tester);
      expect(tools.reading, isFalse);
      await tester.pump(FingerReading.idle);
      await tester.pumpAndSettle();
      expect(tools.reading, isFalse, reason: 'the new page is empty');

      // Fingers navigate anyway once a stylus was seen.
      s.preferences.stylusOnly = true;
      await tester.pump();
      expect(tools.reading, isFalse);
      expect(tools.fingersNavigate, isTrue);
      await tester.pump(FingerReading.idle * 2);
      expect(tools.reading, isFalse);
      await closeEditor(tester);
    });

    testWidgets('a planner page with links and nothing written opens in reading', (tester) async {
      final (s, _) = await pumpEditor(tester, size: phone);
      await closeEditor(tester);
      final papers = PlannerPlan(
        start: DateTime.utc(2026, 10, 1),
        linked: true,
      ).papersFor(PaperStyle.monthlyCalendar);
      final planner = s.notebooks.create(
        title: 'Planner',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        papers: papers,
      );
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EditorScreen(notebook: planner),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(toolsOf(tester).reading, isTrue, reason: 'a finger follows its links');
      await closeEditor(tester);
    });

    testWidgets('an empty notebook opens in writing', (tester) async {
      final (s, nb) = await pumpEditor(tester, size: phone);
      await closeEditor(tester);
      final empty = s.notebooks.create(
        title: 'Empty',
        kind: NotebookKind.paged,
        paper: PaperStyle.collegeRuled,
        coverColor: 0,
      );
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EditorScreen(notebook: empty),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(toolsOf(tester).reading, isFalse);
      expect(find.text(tip), findsNothing);
      await closeEditor(tester);
    });
  });
}
