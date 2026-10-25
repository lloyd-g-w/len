import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_tools.dart';
import 'package:len/features/editor/toolbar/tool_cluster.dart';
import 'package:len/features/editor/tools/tool_icons.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'content_golden_test.dart' show loadFonts;

/// The editor's tool glyphs as one sheet, light and dark, at 1× and 2×:
/// the toolbar's tools idle and on the selected plate (with their ink
/// bars), the popovers' glyphs, the shapes, and the Sharp symbols beside
/// them for weight.
void main() {
  for (final dpr in [1.0, 2.0]) {
    testWidgets('tool icon sheet at ${dpr.toInt()}x', (tester) async {
      await loadFonts();
      const size = Size(2 * _Sheet.width, _Sheet.height);
      // Golden capture is in logical pixels, so 2× is the sheet scaled up.
      tester.view
        ..physicalSize = size * dpr
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tools = ToolSettings();
      addTearDown(tools.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Transform.scale(
            scale: dpr,
            alignment: Alignment.topLeft,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: size.width,
              maxWidth: size.width,
              minHeight: size.height,
              maxHeight: size.height,
              child: Row(
                children: [
                  _Sheet(tools: tools, theme: AppTheme.light()),
                  _Sheet(tools: tools, theme: AppTheme.dark()),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tool_icons_${dpr.toInt()}x.png'),
      );
    });
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.tools, required this.theme});

  final ToolSettings tools;
  final ThemeData theme;

  static const double width = 640;
  static const double height = 336;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final descriptors = editorTools(tools);
    Widget plate(Widget child, {bool selected = false}) => Container(
      width: Targets.bar,
      height: Targets.bar,
      margin: const EdgeInsets.only(right: Gaps.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Surfaces.pressed(scheme) : null,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: IconTheme.merge(
        data: IconThemeData(
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          fill: selected ? 1 : 0,
        ),
        child: child,
      ),
    );
    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: Row(children: children),
    );
    return Theme(
      data: theme,
      child: Container(
        width: width,
        height: height,
        color: scheme.surface,
        padding: const EdgeInsets.all(Gaps.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row([for (final d in descriptors) plate(ToolGlyph(descriptor: d))]),
            row([
              for (final d in descriptors)
                plate(ToolGlyph(descriptor: d, filled: true), selected: true),
            ]),
            row([for (final k in ToolIconKind.values) plate(ToolIcon(k))]),
            row([for (final k in ShapeKind.drawable) plate(ShapeGlyph(k, size: Glyphs.bar))]),
            row([
              for (final k in ShapeKind.drawable)
                plate(ShapeGlyph(k, size: Glyphs.bar), selected: true),
            ]),
            row([
              for (final s in const [
                Symbols.undo_sharp,
                Symbols.redo_sharp,
                Symbols.mic_sharp,
                Symbols.more_horiz_sharp,
                Symbols.image_sharp,
                Symbols.document_scanner_sharp,
                Symbols.add_circle_sharp,
              ])
                plate(Icon(s)),
            ]),
          ],
        ),
      ),
    );
  }
}
