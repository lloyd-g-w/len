import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/text/text_data.dart';

import 'content_golden_test.dart' show loadFonts, loops, text;
import 'content_tools_ui_test.dart';
import 'pdf_text_export_test.dart' show note;
import 'text_box_ui_test.dart' show ctrl;

/// A canvas with [note] (rich text) at (160, 120) and some ink.
Future<void> richCanvas(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
  await loadFonts();
  await openCanvas(
    tester,
    size: size,
    seed: (s, nb) {
      s.elements.save([
        text(nb.id, const Offset(40, 120), note, width: 320),
        text(
          nb.id,
          const Offset(420, 140),
          TextData.rich(
            text: 'Handwriting font, centred',
            font: TextFont.caveat,
            fontSize: 30,
            color: 0xFF1C7ED6,
            align: TextAlignment.center,
          ),
          width: 300,
        ),
      ]);
      s.strokes.save([
        Stroke(
          id: 'loops',
          surfaceId: nb.id,
          tool: InkTool.ballpoint,
          color: 0xFF1F2937,
          width: 2.5,
          points: loops(const Offset(460, 420), scale: 1.2),
          createdAt: 1,
        ),
      ]);
    },
  );
}

void main() {
  testWidgets('text: editing a rich text box (selection bold, format bar)', (tester) async {
    await richCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(120, 200)]);
    await tester.pumpAndSettle();
    // Select "fresh" (bold, red): the bar shows its format.
    final field = tester.widget<TextField>(find.byKey(const ValueKey('text-box-field')));
    final display = MarkerOffsetsProbe.displayOf(field.controller!.text, 'fresh');
    field.controller!.selection = TextSelection(baseOffset: display, extentOffset: display + 5);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_rich_edit.png'),
    );
  });

  testWidgets('text: format bar on a phone keeps delete and done visible', (tester) async {
    await richCanvas(tester, size: const Size(390, 844));
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(120, 200)]);
    await tester.pumpAndSettle();
    await ctrl(tester, LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_phone_bar.png'),
    );
    // The cut-off controls fade out at the edge: there is more to scroll to.
    expect(find.byKey(const ValueKey('scroll-fade')), findsOneWidget);
  });

  testWidgets('text: font picker shows every bundled font in itself', (tester) async {
    await richCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(120, 200)]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('font-menu')));
    await tester.pumpAndSettle();
    for (final f in TextFont.values) {
      expect(find.text(f.label), findsWidgets);
    }
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_font_picker.png'),
    );
  });

  testWidgets('lasso: style panel for text boxes and ink', (tester) async {
    await richCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [
      Offset(400, 100),
      Offset(760, 100),
      Offset(760, 560),
      Offset(400, 560),
      Offset(400, 105),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Style'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_lasso_style.png'),
    );
  });
}

/// Finds a word in the field's display text.
abstract final class MarkerOffsetsProbe {
  static int displayOf(String display, String word) => display.indexOf(word);
}
