import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_flow_chains.dart';

import 'text_flow_editor_test.dart';

/// [n] Hebrew lines.
String hebrew(int n) => [for (var i = 0; i < n; i++) 'שורה $i'].join('\n');

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('a right-to-left box flows over the page edge; the caret crosses it', (tester) async {
    final (services, nb) = await openNotebook(tester);
    final pages = services.pages.pagesOf(nb.id);
    final page = pages.first;
    final margin = FlowPage.marginOf(page.size);
    await typeBox(tester, Offset(page.width / 2, page.height - margin - 100), hebrew(10));
    final s = session(tester);
    final c = controller(tester);
    expect(s.frames, hasLength(2));
    expect(c.plan.base, TextDirection.rtl);

    // The next page's text starts at its top margin, on the right.
    final at = breakOf(tester);
    final o = c.plan.offsets;
    final top = doc(tester).pageViewport.toScreen(s.frames[1].topRight);
    final start = caretAt(tester, o.toDisplay(at));
    expect(start.dy, closeTo(top.dy, 1));
    expect(start.dx, closeTo(top.dx, 6));

    // ← is forwards in right-to-left text: from the end of page one it
    // steps over the page edge, → comes back.
    c.selection = TextSelection.collapsed(offset: o.toDisplay(at - 1));
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(c.modelSelection.start, at);
    expect(caretAt(tester, c.selection.extentOffset).dy, closeTo(top.dy, 1));
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(c.modelSelection.start, at - 1);

    // ↑ from the next page's first line goes back to the page before (not
    // into the room over the edge).
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(c.modelSelection.start, lessThan(at));
    expect(o.isPageBreak(c.selection.extentOffset), isFalse);

    // Typing at the start of the next page goes there.
    c.selection = TextSelection.collapsed(offset: o.toDisplay(at));
    await tester.pump();
    await tester.enterText(field, c.text.replaceRange(c.selection.start, c.selection.start, 'א'));
    await tester.pumpAndSettle();
    expect(c.data.text, hebrew(10).replaceRange(at, at, 'א'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final head = textOn(services, page.id).single;
    final next = textOn(services, pages[1].id).single;
    final flow = TextFlowChains.flowOf(next)!;
    expect((flow.from, flow.joined, flow.direction), (head.id, false, TextDirection.rtl));
    expect(next.rect.right, closeTo(head.rect.right, 0.01));
    expect(
      TextFlow.join([TextData.fromJson(head.data), TextData.fromJson(next.data)]).text,
      hebrew(10).replaceRange(at, at, 'א'),
    );
  });

  final paragraph = 'שלום ${List.filled(160, 'עולם').join(' ')}';
  for (final (name, text) in [
    ('in a right-to-left box', paragraph),
    ('in a left-to-right box', 'Notes\n$paragraph'),
  ]) {
    testWidgets('a right-to-left paragraph split by the page edge edits as one $name', (
      tester,
    ) async {
      final (services, nb) = await openNotebook(tester);
      final pages = services.pages.pagesOf(nb.id);
      final page = pages.first;
      final margin = FlowPage.marginOf(page.size);
      await typeBox(tester, Offset(page.width / 2, page.height - margin - 100), text);
      final s = session(tester);
      final c = controller(tester);
      expect(s.frames, hasLength(2));
      final b = s.breaksFor(c.data).first;
      expect(b.soft, isTrue);
      final o = c.plan.offsets;
      final top = doc(tester).pageViewport.toScreen(s.frames[1].topRight);
      final start = caretAt(tester, o.toDisplay(b.at));
      expect(start.dy, closeTo(top.dy, 1));
      expect(start.dx, closeTo(top.dx, 6));

      // Backspace at the next page's start deletes the character before it
      // (the space ending page one), not the room.
      c.selection = TextSelection.collapsed(offset: o.toDisplay(b.at));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.backspace);
      expect(c.data.text, text.replaceRange(b.at - 1, b.at, ''));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final head = textOn(services, page.id).single;
      final next = textOn(services, pages[1].id).single;
      final flow = TextFlowChains.flowOf(next)!;
      expect((flow.joined, flow.direction), (true, TextDirection.rtl));
      expect(
        TextFlow.join([TextData.fromJson(head.data), TextData.fromJson(next.data)]).text,
        text.replaceRange(b.at - 1, b.at, ''),
      );
    });
  }
}
