import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/tools/text_options_panel.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts, text;
import 'content_tools_ui_test.dart';
import 'pdf_text_export_test.dart' show note;
import 'text_box_ui_test.dart' show ctrl;

void main() {
  testWidgets('the format bar sets the box\'s paragraph spacing; undo takes it back', (
    tester,
  ) async {
    final data = TextData.rich(text: 'First\nSecond\nThird', fontSize: 20);
    final (s, nb) = await openCanvas(
      tester,
      seed: (s, nb) => s.elements.save([text(nb.id, const Offset(100, 120), data, width: 300)]),
    );
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(140, 130)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    final before = tester.getSize(field).height;
    await tester.tap(find.byTooltip('Paragraph spacing'));
    await tester.pumpAndSettle();
    for (final s in ParagraphSpacing.values) {
      expect(find.text(s.label), findsOneWidget);
    }
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();
    // The field takes the space in at once: two gaps of a font size.
    expect(tester.getSize(field).height, closeTo(before + 40, 1));
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final box = liveElements(s, nb.id).single;
    final stored = TextData.fromJson(box.data);
    expect(stored.spacing, ParagraphSpacing.large);
    expect(box.rect.height, closeTo(TextLayout.heightOf(stored, 300), 0.5));
    // Remembered for new boxes, like the box's other defaults.
    final session = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;
    expect(session.tools.textStyle.spacing, ParagraphSpacing.large);

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(TextData.fromJson(liveElements(s, nb.id).single.data).spacing, ParagraphSpacing.none);
  });

  testWidgets('the Text tool\'s options set the spacing of new boxes', (tester) async {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: TextOptionsPanel(tools: tools)),
          ),
        ),
      ),
    );
    expect(find.text('None'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paragraph-spacing-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Small'));
    await tester.pumpAndSettle();
    expect(tools.textStyle.spacing, ParagraphSpacing.small);
    expect(find.text('Small'), findsOneWidget);
  });

  testWidgets('spaced paragraphs on the canvas and while edited; the phone\'s ⋯ offers them', (
    tester,
  ) async {
    await loadFonts();
    final spaced = note.copyWith(spacing: ParagraphSpacing.medium);
    await openCanvas(
      tester,
      size: const Size(390, 844),
      seed: (s, nb) => s.elements.save([
        text(nb.id, const Offset(20, 120), spaced, width: 340),
        text(
          nb.id,
          const Offset(20, 440),
          TextData.rich(text: 'שלום עולם\nEnglish line\nسلام', spacing: ParagraphSpacing.large),
          width: 340,
        ),
      ]),
    );
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(120, 160)]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Medium paragraph spacing'), findsOneWidget);
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_paragraph_spacing.png'),
    );
    await tester.tap(find.text('Small paragraph spacing'));
    await tester.pumpAndSettle();
    final session = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;
    expect(session.tools.textStyle.spacing, ParagraphSpacing.small);
  });
}
