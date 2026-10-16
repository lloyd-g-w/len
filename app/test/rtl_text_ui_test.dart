import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'content_golden_test.dart' show loadFonts, text;
import 'content_tools_ui_test.dart';
import 'rtl_text_golden_test.dart' show arabic;
import 'rtl_text_test.dart' show mixed, paragraphs;

RichTextController _controller(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byKey(const ValueKey('text-box-field')));
  return field.controller! as RichTextController;
}

void main() {
  testWidgets('text: a right-to-left box grows to the left, its bar and arrows mirror', (
    tester,
  ) async {
    final (services, nb) = await openCanvas(tester);
    final field = find.byKey(const ValueKey('text-box-field'));
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 300)]);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Hello');
    await key(tester, LogicalKeyboardKey.escape);
    await mouseDrag(tester, const [Offset(300, 500)]);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'ש');
    await tester.pump();
    // The start edge stays where the box began (its empty width).
    final started = _controller(tester);
    expect(started.plan.base, TextDirection.rtl);
    await tester.enterText(field, 'שלום עולם');
    await tester.pumpAndSettle();
    // Start alignment shows as right-aligned here.
    expect(find.byIcon(Symbols.format_align_right_sharp), findsOneWidget);
    expect(find.byIcon(Symbols.format_align_left_sharp), findsNothing);
    final c = _controller(tester);
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await tester.pump();
    // Left moves on through right-to-left text: forwards; right goes back.
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(c.modelSelection, const TextRange.collapsed(8));
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(c.modelSelection, const TextRange.collapsed(8));
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final boxes = liveElements(services, nb.id)..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    final [ltr, rtl] = boxes;
    expect(TextData.fromJson(rtl.data).text, 'שלום עולם');
    expect(rtl.rect.width, greaterThan(60));
    expect(rtl.rect.right, closeTo(ltr.rect.left + 24, 1));
  });

  testWidgets('text: editing a box mixing English, Hebrew and Arabic', (tester) async {
    await loadFonts();
    await openCanvas(
      tester,
      seed: (s, nb) => s.elements.save([
        text(nb.id, const Offset(60, 120), mixed, width: 300),
        text(nb.id, const Offset(520, 120), arabic, width: 300),
      ]),
    );
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(100, 132)]);
    await tester.pumpAndSettle();
    final c = _controller(tester);
    // Select from inside the Hebrew item to inside the Arabic paragraph.
    final paras = paragraphs(mixed);
    final from = c.plan.offsets.toDisplay(paras[1].$1 + 5);
    final to = c.plan.offsets.toDisplay(paras[2].$1 + 6);
    c.selection = TextSelection(baseOffset: from, extentOffset: to);
    await tester.pumpAndSettle();
    expect(c.caretDirection, TextDirection.rtl);
    expect(find.byIcon(Symbols.format_align_right_sharp), findsOneWidget);
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_rtl_editing.png'),
    );
  });
}
